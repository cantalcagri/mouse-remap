#!/bin/sh
# Installs (or reinstalls) a LaunchAgent so `remap` starts at login and is relaunched if it exits.
# Usage: ./install-launchagent.sh          install and start
#        ./install-launchagent.sh remove   stop and remove
set -e
LABEL=com.cantalcagri.mouse-remap
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/remap"
LOG="$HOME/Library/Logs/mouse-remap.log"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "$1" = "remove" ]; then rm -f "$PLIST"; echo "removed"; exit 0; fi

[ -x "$BIN" ] || { echo "building..."; swiftc -O "$DIR/remap.swift" -o "$BIN"; }
pkill -f "$BIN" 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 4
if pgrep -f "$BIN" >/dev/null 2>&1; then
  echo "running. It will start automatically at every login."
else
  echo "installed, but not running yet. Grant Accessibility to the binary itself:"
  echo "  System Settings > Privacy & Security > Accessibility > '+' > choose $BIN"
  echo "launchd retries every 5 seconds, so it starts on its own once granted. Log: $LOG"
fi
