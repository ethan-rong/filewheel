#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcrun --find swift >/dev/null 2>&1; then
  echo 'Install Apple Command Line Tools with: xcode-select --install'
  exit 1
fi

swift build -c release
filewheel_bin="$(swift build -c release --show-bin-path)/FileWheel"
filewheel_root="$HOME/Library/Application Support/FileWheel"
filewheel_bundle="$filewheel_root/FileWheel.app"
filewheel_agent="$HOME/Library/LaunchAgents/io.github.ethan-rong.filewheel.plist"
filewheel_uid="$(id -u)"

# Build before stopping an existing installation, so a build failure leaves it working.
launchctl bootout "gui/$filewheel_uid" "$filewheel_agent" 2>/dev/null || true
mkdir -p "$filewheel_bundle/Contents/MacOS" "$HOME/Library/LaunchAgents"
cp "$filewheel_bin" "$filewheel_bundle/Contents/MacOS/FileWheel"
cat > "$filewheel_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.ethan-rong.filewheel</string>
<key>CFBundleName</key><string>FileWheel</string>
<key>CFBundleDisplayName</key><string>FileWheel</string>
<key>CFBundleExecutable</key><string>FileWheel</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --identifier io.github.ethan-rong.filewheel "$filewheel_bundle"

# plutil handles XML escaping for paths containing ampersands or other special characters.
plutil -create xml1 "$filewheel_agent"
plutil -insert Label -string io.github.ethan-rong.filewheel "$filewheel_agent"
plutil -insert ProgramArguments -array "$filewheel_agent"
plutil -insert ProgramArguments.0 -string "$filewheel_bundle/Contents/MacOS/FileWheel" "$filewheel_agent"
plutil -insert RunAtLoad -bool YES "$filewheel_agent"
plutil -insert ProcessType -string Interactive "$filewheel_agent"
plutil -insert LimitLoadToSessionType -string Aqua "$filewheel_agent"
launchctl bootstrap "gui/$filewheel_uid" "$filewheel_agent"
echo 'FileWheel is running in your menu bar and will start when you log in.'
echo 'Enable FileWheel in System Settings → Privacy & Security → Accessibility.'
echo 'Audio/video: brew install ffmpeg   |   WebP output: brew install webp'
