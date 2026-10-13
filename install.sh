#!/bin/bash
# Builds Agent Buddy, installs the Claude Code / Codex hooks, and starts it at login.
# Run it with: bash install.sh. Safe to run again (after a git pull, or to rebuild).
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/AgentBuddy.app"
HOOK="$HOME/.agent-buddy/buddy-hook"
PLIST="$HOME/Library/LaunchAgents/io.github.agentbuddy.plist"

echo "▸ Checking requirements…"
if [ "$(uname)" != "Darwin" ]; then echo "Agent Buddy runs on macOS only."; exit 1; fi
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then echo "Agent Buddy needs macOS 14 (Sonoma) or later; this Mac has $(sw_vers -productVersion)."; exit 1; fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple's command line tools are missing. Run:  xcode-select --install"
  echo "then run: bash install.sh."
  exit 1
fi
[ -x /usr/bin/python3 ] || { echo "python3 is missing (it comes with the command line tools: xcode-select --install)."; exit 1; }
for tool in claude codex gh aws herdr; do
  command -v "$tool" >/dev/null 2>&1 && echo "  ✓ $tool" || echo "  · $tool not found (optional)"
done

mkdir -p "$HOME/.agent-buddy"
if [ ! -f "$HOME/.agent-buddy/config.json" ]; then
  cp config.example.json "$HOME/.agent-buddy/config.json"
  echo "▸ Created ~/.agent-buddy/config.json from config.example.json (edit it to add your repos, sites, …)"
fi

echo "▸ Building… (about a minute the first time)"
mkdir -p build "$HOME/.agent-buddy" "$HOME/Applications" "$HOME/Library/LaunchAgents"
swiftc -O -swift-version 5 Sources/App/*.swift -o build/AgentBuddy
swiftc -O -swift-version 5 Sources/Hook/main.swift -o build/buddy-hook

echo "▸ Installing app → $APP"
pkill -x AgentBuddy 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp build/AgentBuddy "$APP/Contents/MacOS/AgentBuddy"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.agentbuddy</string>
  <key>CFBundleName</key><string>AgentBuddy</string>
  <key>CFBundleExecutable</key><string>AgentBuddy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force -s - "$APP" >/dev/null 2>&1 || true
cp build/buddy-hook "$HOOK"

echo "▸ Registering Claude Code hooks in ~/.claude/settings.json (backup: settings.json.bak-agent-buddy)"
HOOK="$HOOK" /usr/bin/python3 - <<'PY'
import json, os, shutil
p = os.path.expanduser("~/.claude/settings.json")
s = {}
if os.path.exists(p):
    if not os.path.exists(p + ".bak-agent-buddy"): shutil.copy(p, p + ".bak-agent-buddy")
    with open(p) as f: s = json.load(f)
cmd = os.environ["HOOK"]
hooks = s.setdefault("hooks", {})
for ev in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "PermissionRequest", "Stop", "SubagentStop", "SessionEnd"]:
    groups = [g for g in hooks.get(ev, [])
              if not any("buddy-hook" in h.get("command", "") for h in g.get("hooks", []))]
    hook = {"type": "command", "command": cmd}
    # These two may wait for your answer from Agent Buddy (remote mode only).
    if ev in ("PermissionRequest", "Stop"): hook["timeout"] = 600
    entry = {"hooks": [hook]}
    if ev in ("PostToolUse", "PermissionRequest"): entry["matcher"] = "*"
    if ev == "PreToolUse": entry["matcher"] = "Bash"   # only shell commands are checked for production
    groups.append(entry)
    hooks[ev] = groups
with open(p, "w") as f: json.dump(s, f, indent=2)
PY

echo "▸ Registering Codex hooks in ~/.codex/hooks.json (Codex: Settings → Hooks → Trust all)"
if [ -d "$HOME/.codex" ]; then
HOOK="$HOOK" /usr/bin/python3 - <<'PY'
import json, os, shutil
p = os.path.expanduser("~/.codex/hooks.json")
s = {}
if os.path.exists(p):
    if not os.path.exists(p + ".bak-agent-buddy"): shutil.copy(p, p + ".bak-agent-buddy")
    with open(p) as f: s = json.load(f)
hooks = s.setdefault("hooks", {})
for ev in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]:
    groups = [g for g in hooks.get(ev, [])
              if not any("buddy-hook" in h.get("command", "") for h in g.get("hooks", []))]
    groups.append({"hooks": [{"type": "command", "command": os.environ["HOOK"], "timeout": 5}]})
    hooks[ev] = groups
with open(p, "w") as f: json.dump(s, f, indent=2)
PY
fi

echo "▸ Installing the buddy command (buddy say \"…\")"
BIN_DIR=/opt/homebrew/bin; [ -w "$BIN_DIR" ] || BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
printf '#!/bin/sh\n# Agent Buddy: buddy say "<message>" [--urgent]\nexec "$HOME/.agent-buddy/buddy-hook" "$@"\n' > "$BIN_DIR/buddy"
chmod +x "$BIN_DIR/buddy"

echo "▸ Telling Claude Code and Codex when to use buddy say"
for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
  [ -d "$(dirname "$f")" ] || continue
  touch "$f"
  if ! grep -q "agent-buddy:start" "$f"; then
    cat >> "$f" <<'EOF'

<!-- agent-buddy:start -->
## Agent Buddy
When you finish something I'm waiting on, need my decision, or are blocked on me,
run `buddy say "<one short sentence>"` (add `--urgent` if I must act now).
Under 20 words. No secrets. Not for routine progress.
<!-- agent-buddy:end -->
EOF
  fi
done

echo "▸ Starting at login (LaunchAgent)"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>io.github.agentbuddy</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/AgentBuddy</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
</dict></plist>
EOF
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "✅ Agent Buddy is running. Restart open Claude Code sessions so they pick up the hooks."
