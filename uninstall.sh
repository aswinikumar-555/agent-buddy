#!/bin/bash
# Removes Agent Buddy: the app, its login item, its hooks and status line, the buddy command,
# the note for agents in CLAUDE.md / AGENTS.md, and ~/.agent-buddy.
set -uo pipefail
APP="$HOME/Applications/AgentBuddy.app"
PLIST="$HOME/Library/LaunchAgents/io.github.agentbuddy.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null
pkill -x AgentBuddy 2>/dev/null
[ -x "$APP/Contents/MacOS/AgentBuddy" ] && "$APP/Contents/MacOS/AgentBuddy" --uninstall
rm -f "$PLIST"
rm -rf "$APP" "$HOME/.agent-buddy"
echo "Agent Buddy removed."
