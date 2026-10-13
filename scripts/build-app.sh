#!/bin/bash
# Builds build/AgentBuddy.app (the app, the hook program and the example config).
#   bash scripts/build-app.sh               # for this Mac
#   bash scripts/build-app.sh --universal   # Apple silicon + Intel, for a release
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
APP=build/AgentBuddy.app
mkdir -p build

if [ "${1:-}" = "--universal" ]; then
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos14" Sources/App/*.swift -o "build/AgentBuddy-$arch"
    swiftc -O -swift-version 5 -target "$arch-apple-macos14" Sources/Hook/main.swift -o "build/buddy-hook-$arch"
  done
  lipo -create build/AgentBuddy-arm64 build/AgentBuddy-x86_64 -output build/AgentBuddy
  lipo -create build/buddy-hook-arm64 build/buddy-hook-x86_64 -output build/buddy-hook
  rm -f build/AgentBuddy-arm64 build/AgentBuddy-x86_64 build/buddy-hook-arm64 build/buddy-hook-x86_64
else
  swiftc -O -swift-version 5 Sources/App/*.swift -o build/AgentBuddy
  swiftc -O -swift-version 5 Sources/Hook/main.swift -o build/buddy-hook
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/AgentBuddy "$APP/Contents/MacOS/AgentBuddy"
cp build/buddy-hook config.example.json "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.agentbuddy</string>
  <key>CFBundleName</key><string>AgentBuddy</string>
  <key>CFBundleDisplayName</key><string>Agent Buddy</string>
  <key>CFBundleExecutable</key><string>AgentBuddy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Agent Buddy reads your calendar to give you a heads-up before meetings. Nothing leaves your Mac.</string>
</dict></plist>
PLIST
codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "Built $APP ($VERSION)"
