#!/bin/bash
#
# Rebuild ReflexWhoop and reinstall it on the iPhone, so a free Apple ID build
# never reaches its seven-day expiry.
#
# A free (Personal Team) provisioning profile lasts seven days. When it lapses the
# app stops launching, though its data survives on disk. Reinstalling a freshly
# signed build of the same bundle ID with the same certificate is an upgrade
# install: iOS keeps the container, so the archive comes through untouched.
#
# The archive is the one thing here that cannot be recreated, so the app's
# Documents directory is copied off the phone before anything is installed over
# it. Backups live outside the repository and are never committed.
#
# Usage:
#   scripts/refresh_device_install.sh              # refresh now
#   scripts/refresh_device_install.sh --if-due     # only if the last one has aged out
#   scripts/refresh_device_install.sh --device NAME|UDID
#   scripts/refresh_device_install.sh --no-backup  # skip the container copy
#
# Environment:
#   REFLEXWHOOP_DEVICE        device name or UDID, same as --device
#   REFLEXWHOOP_STATE_DIR     state, backups and logs (default ~/Library/Application Support/ReflexWhoop)
#   REFLEXWHOOP_REFRESH_DAYS  age at which --if-due acts (default 5)
#   REFLEXWHOOP_KEEP_BACKUPS  backups to retain (default 8)

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly STATE_DIR="${REFLEXWHOOP_STATE_DIR:-$HOME/Library/Application Support/ReflexWhoop}"
readonly BACKUP_DIR="$STATE_DIR/backups"
readonly STAMP_FILE="$STATE_DIR/last-install"
readonly DERIVED_DATA="$HOME/Library/Caches/ReflexWhoop/DerivedData"
readonly REFRESH_DAYS="${REFLEXWHOOP_REFRESH_DAYS:-5}"
readonly KEEP_BACKUPS="${REFLEXWHOOP_KEEP_BACKUPS:-8}"

device="${REFLEXWHOOP_DEVICE:-}"
if_due=0
backup=1

while [ $# -gt 0 ]; do
  case "$1" in
    --device) device="${2:?--device needs a name or UDID}"; shift 2 ;;
    --if-due) if_due=1; shift ;;
    --no-backup) backup=0; shift ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's|^# \{0,1\}||'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# launchd has no one to show a failure to, so say it with a notification as well
# as in the log. Quoting matters: the message reaches AppleScript as a string.
notify() {
  local message="${1//\"/}"
  osascript -e "display notification \"$message\" with title \"ReflexWhoop\" subtitle \"Device refresh failed\"" \
    >/dev/null 2>&1 || true
}

fail() { log "FAILED: $*"; notify "$*"; exit 1; }

# The install is due when the last successful one has aged past REFRESH_DAYS, or
# when there has never been one. Checking the age here rather than in launchd's
# schedule means a day the phone was away is retried tomorrow instead of lost.
install_is_due() {
  [ -f "$STAMP_FILE" ] || return 0
  local last now
  last="$(cat "$STAMP_FILE" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  [ $(( (now - last) / 86400 )) -ge "$REFRESH_DAYS" ]
}

# The only physical device devicectl knows about. Simulators carry
# hardwareProperties.reality = "simulated"; a real phone has no such field.
resolve_device() {
  local json
  json="$(mktemp)"
  xcrun devicectl list devices --quiet --json-output "$json" >/dev/null 2>&1 \
    || { rm -f "$json"; return 1; }
  python3 - "$json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
physical = [d for d in devices
            if d.get("hardwareProperties", {}).get("reality") != "simulated"]
if len(physical) != 1:
    names = ", ".join(d["deviceProperties"].get("name", "?") for d in physical) or "none"
    sys.exit(f"expected exactly one physical device, found {len(physical)}: {names}")
print(physical[0]["hardwareProperties"]["udid"])
PY
  local status=$?
  rm -f "$json"
  return $status
}

bundle_id() {
  xcodebuild -project "$REPO/ReflexWhoop.xcodeproj" -scheme ReflexWhoop \
    -configuration Debug -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}'
}

# Pull the app's Documents directory — the SQLite file plus its write-ahead log —
# to a timestamped folder before installing over it. Best effort: a first install
# has no container yet, and that is not a reason to stop.
back_up_archive() {
  local udid="$1" bundle="$2" destination
  destination="$BACKUP_DIR/$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$destination"
  if xcrun devicectl device copy from --device "$udid" \
       --domain-type appDataContainer --domain-identifier "$bundle" \
       --source Documents --destination "$destination" --quiet >/dev/null 2>&1; then
    log "archive backed up to $destination"
  else
    rmdir "$destination" 2>/dev/null || true
    log "no archive to back up yet (app not installed, or the phone refused the copy)"
  fi
}

prune_backups() {
  [ -d "$BACKUP_DIR" ] || return 0
  local stale
  stale="$(ls -1 "$BACKUP_DIR" 2>/dev/null | sort -r | tail -n "+$((KEEP_BACKUPS + 1))")"
  [ -n "$stale" ] || return 0
  while IFS= read -r old; do
    rm -rf "$BACKUP_DIR/$old"
    log "pruned old backup $old"
  done <<< "$stale"
}

main() {
  mkdir -p "$STATE_DIR" "$BACKUP_DIR"

  if [ "$if_due" -eq 1 ] && ! install_is_due; then
    log "last install is under $REFRESH_DAYS days old; nothing to do"
    exit 0
  fi

  if [ -z "$device" ]; then
    device="$(resolve_device)" || fail "no iPhone found. Plug it in, unlock it, and trust this Mac."
  fi

  local bundle
  bundle="$(bundle_id)"
  [ -n "$bundle" ] || fail "could not read PRODUCT_BUNDLE_IDENTIFIER from the project."
  log "device $device, bundle $bundle"

  if [ "$backup" -eq 1 ]; then
    back_up_archive "$device" "$bundle"
  fi

  # -allowProvisioningUpdates is the whole point: it asks Apple for a fresh
  # seven-day profile. Device registration is needed the first time only.
  log "building…"
  xcodebuild build \
    -project "$REPO/ReflexWhoop.xcodeproj" \
    -scheme ReflexWhoop \
    -configuration Debug \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    -quiet \
    || fail "build failed. Check that the Apple ID is still signed into Xcode → Settings → Accounts."

  local app="$DERIVED_DATA/Build/Products/Debug-iphoneos/ReflexWhoop.app"
  [ -d "$app" ] || fail "built, but $app is missing."

  log "installing…"
  xcrun devicectl device install app --device "$device" "$app" --quiet >/dev/null \
    || fail "install failed. Is the phone unlocked and on the same network?"

  date +%s > "$STAMP_FILE"
  prune_backups
  log "installed. Next refresh due in $REFRESH_DAYS days."
}

main "$@"
