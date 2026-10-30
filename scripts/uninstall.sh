#!/bin/bash
set -euo pipefail
filewheel_agent="$HOME/Library/LaunchAgents/io.github.ethan-rong.filewheel.plist"
launchctl bootout "gui/$(id -u)" "$filewheel_agent" 2>/dev/null || true
rm -f "$filewheel_agent"
rm -rf "$HOME/Library/Application Support/FileWheel"
echo 'FileWheel removed. Converted files are untouched.'
echo 'You can remove its Accessibility entry in System Settings.'
