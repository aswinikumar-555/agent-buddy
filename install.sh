#!/bin/bash
# Builds Agent Buddy from source, connects it to Claude Code and Codex, and starts it at login.
# Run it with: bash install.sh. Safe to run again (after a git pull, or to rebuild).
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/AgentBuddy.app"
PLIST="$HOME/Library/LaunchAgents/io.github.agentbuddy.plist"

echo "▸ Checking requirements…"
if [ "$(uname)" != "Darwin" ]; then echo "Agent Buddy runs on macOS only."; exit 1; fi
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then echo "Agent Buddy needs macOS 14 (Sonoma) or later; this Mac has $(sw_vers -productVersion)."; exit 1; fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple's command line tools are missing. Run:  xcode-select --install"
  echo "then run: bash install.sh. (Or download the ready-made app from the Releases page instead.)"
  exit 1
fi
for tool in claude codex gh aws gcloud herdr; do
  command -v "$tool" >/dev/null 2>&1 && echo "  ✓ $tool" || echo "  · $tool not found (optional)"
done

echo "▸ Building… (about a minute the first time)"
bash scripts/build-app.sh

echo "▸ Installing app → $APP"
pkill -x AgentBuddy 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
cp -R build/AgentBuddy.app "$APP"

echo "▸ Connecting to Claude Code and Codex"
"$APP/Contents/MacOS/AgentBuddy" --setup --launch-agent

echo "▸ Starting at login (LaunchAgent)"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "✅ Agent Buddy is running. Restart open Claude Code sessions so they pick up the hooks."
