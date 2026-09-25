#!/bin/bash
#
# Install (or remove) the launchd agent that keeps the phone's build alive.
#
# The agent wakes once a day and runs refresh_device_install.sh --if-due, which
# rebuilds and reinstalls only when the last install has aged past five days. A
# daily check rather than a weekly alarm means a day the phone was away is simply
# retried tomorrow, well inside the seven-day window.
#
# The generated plist holds this checkout's path, so it is written to
# ~/Library/LaunchAgents and never committed.
#
# Usage:
#   scripts/install_refresh_agent.sh              # install and start
#   scripts/install_refresh_agent.sh --uninstall
#   scripts/install_refresh_agent.sh --status

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LABEL="com.reflexwhoop.deviceRefresh"
readonly PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
readonly LOG_DIR="$HOME/Library/Logs/ReflexWhoop"
readonly LOG="$LOG_DIR/device-refresh.log"
readonly DOMAIN="gui/$(id -u)"

uninstall() {
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "removed $LABEL. The app on the phone is untouched; it will lapse in up to seven days."
}

status() {
  if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    echo "$LABEL is loaded."
  else
    echo "$LABEL is not loaded."
  fi
  echo "plist: $PLIST"
  echo "log:   $LOG"
  local stamp="$HOME/Library/Application Support/ReflexWhoop/last-install"
  if [ -f "$stamp" ]; then
    echo "last install: $(date -r "$(cat "$stamp")" '+%Y-%m-%d %H:%M:%S')"
  else
    echo "last install: never"
  fi
}

install() {
  mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"

  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$REPO/scripts/refresh_device_install.sh</string>
		<string>--if-due</string>
	</array>
	<key>StartInterval</key>
	<integer>86400</integer>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$LOG</string>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
	<key>ProcessType</key>
	<string>Background</string>
	<key>LowPriorityIO</key>
	<true/>
</dict>
</plist>
PLIST_EOF

  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$PLIST"
  echo "installed $LABEL — checks daily, refreshes when the build is five days old."
  echo "log: $LOG"
}

case "${1:---install}" in
  --install) install ;;
  --uninstall) uninstall ;;
  --status) status ;;
  -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's|^# \{0,1\}||' ;;
  *) echo "unknown argument: $1" >&2; exit 64 ;;
esac
