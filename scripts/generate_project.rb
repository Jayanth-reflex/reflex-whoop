#!/usr/bin/env ruby
# Generates ReflexWhoop.xcodeproj from scratch. Re-run this after adding/removing
# source files (it walks ReflexWhoop/ and ReflexWhoopTests/ on disk and rebuilds
# the group tree + compile-sources list each time) — do not hand-edit the .xcodeproj.
#
# No xcodegen/tuist available in this environment (Homebrew's prefix is owned by
# root here, so `brew install xcodegen` can't run without a password prompt this
# script can't answer) — hence a plain Ruby script against the `xcodeproj` gem
# (installed with `gem install --user-install xcodeproj`, no sudo needed).

require 'xcodeproj'
require 'securerandom'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'ReflexWhoop.xcodeproj')
APP_NAME = 'ReflexWhoop'
TEST_NAME = 'ReflexWhoopTests'
BUNDLE_ID = 'com.reflexwhoop.app'
DEPLOYMENT_TARGET = '17.0'

project = Xcodeproj::Project.new(PROJECT_PATH)

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

app_target = project.new_target(:application, APP_NAME, :ios, DEPLOYMENT_TARGET)
test_target = project.new_target(:unit_test_bundle, TEST_NAME, :ios, DEPLOYMENT_TARGET)
test_target.add_dependency(app_target)

# ---------------------------------------------------------------------------
# GRDB.swift as a remote Swift package
# ---------------------------------------------------------------------------

grdb_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
grdb_ref.repositoryURL = 'https://github.com/groue/GRDB.swift.git'
grdb_ref.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '6.0.0' }
project.root_object.package_references << grdb_ref

def link_grdb(project, target, package_ref)
  product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product_dep.package = package_ref
  product_dep.product_name = 'GRDB'
  target.package_product_dependencies << product_dep

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product_dep
  target.frameworks_build_phase.files << build_file
end

link_grdb(project, app_target, grdb_ref)
link_grdb(project, test_target, grdb_ref)

# ---------------------------------------------------------------------------
# Groups + file references, walked from disk
# ---------------------------------------------------------------------------

def add_files_recursively(project_group, fs_dir, target, resource_extensions: [])
  Dir.children(fs_dir).sort.each do |entry|
    next if entry.start_with?('.')
    full_path = File.join(fs_dir, entry)

    if File.directory?(full_path)
      # .xcassets is a single file reference in Xcode's model, not a walked group.
      if entry.end_with?('.xcassets')
        ref = project_group.new_reference(full_path)
        target.resources_build_phase.add_file_reference(ref)
      else
        subgroup = project_group.new_group(entry, full_path)
        add_files_recursively(subgroup, full_path, target, resource_extensions: resource_extensions)
      end
    else
      ref = project_group.new_reference(full_path)
      ext = File.extname(entry)
      if ext == '.swift'
        target.add_file_references([ref])
      elsif resource_extensions.include?(ext)
        target.resources_build_phase.add_file_reference(ref)
      end
      # Info.plist is intentionally not added to any build phase — it's referenced
      # via the INFOPLIST_FILE build setting instead.
    end
  end
end

app_group = project.main_group.new_group(APP_NAME, File.join(ROOT, APP_NAME))
add_files_recursively(app_group, File.join(ROOT, APP_NAME), app_target)

test_group = project.main_group.new_group(TEST_NAME, File.join(ROOT, TEST_NAME))
add_files_recursively(test_group, File.join(ROOT, TEST_NAME), test_target, resource_extensions: ['.json'])

# ---------------------------------------------------------------------------
# Build settings
# ---------------------------------------------------------------------------

common_settings = {
  'SWIFT_VERSION' => '5.0',
  'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
  'TARGETED_DEVICE_FAMILY' => '1', # iPhone only
  'CODE_SIGN_STYLE' => 'Automatic',
  'ENABLE_PREVIEWS' => 'YES',
  # Free Apple ID (Personal Team, per the design doc's constraints section):
  # no push/iCloud/App Groups, and every on-device build expires after 7 days
  # and needs re-installing (re-run devicectl install or hit Run in Xcode —
  # this team ID itself doesn't change).
  'DEVELOPMENT_TEAM' => 'YOUR_TEAM_ID',
}

project.build_configurations.each do |config|
  config.build_settings.merge!(common_settings)
end

app_target.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'PRODUCT_NAME' => APP_NAME,
    'INFOPLIST_FILE' => "#{APP_NAME}/Info.plist",
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'SWIFT_EMIT_LOC_STRINGS' => 'YES',
    'CODE_SIGN_STYLE' => 'Automatic',
    'DEVELOPMENT_ASSET_PATHS' => '',
    'ENABLE_HARDENED_RUNTIME' => 'NO',
  )
end

test_target.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.tests",
    'PRODUCT_NAME' => TEST_NAME,
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'TEST_HOST' => "$(BUILT_PRODUCTS_DIR)/#{APP_NAME}.app/#{APP_NAME}",
    'BUNDLE_LOADER' => '$(TEST_HOST)',
    'CODE_SIGN_STYLE' => 'Automatic',
  )
end

# ---------------------------------------------------------------------------
# Scheme — shared so `xcodebuild -scheme ReflexWhoop test` works without first
# opening the project in Xcode (which is what normally creates the user scheme).
# ---------------------------------------------------------------------------

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(test_target)
scheme.set_launch_target(app_target)
scheme.save_as(PROJECT_PATH, APP_NAME, true)

project.save

puts "Generated #{PROJECT_PATH}"
