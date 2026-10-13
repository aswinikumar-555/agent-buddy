#!/bin/bash
# Removes Agent Buddy, its LaunchAgent, and its Claude Code hooks.
set -uo pipefail
PLIST="$HOME/Library/LaunchAgents/io.github.agentbuddy.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null
pkill -x AgentBuddy 2>/dev/null
rm -f "$PLIST"
rm -rf "$HOME/Applications/AgentBuddy.app" "$HOME/.agent-buddy"
/usr/bin/python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
if os.path.exists(p):
    with open(p) as f: s = json.load(f)
    hooks = s.get("hooks", {})
    for ev in list(hooks):
        hooks[ev] = [g for g in hooks[ev]
                     if not any("buddy-hook" in h.get("command", "") for h in g.get("hooks", []))]
        if not hooks[ev]: del hooks[ev]
    if not hooks: s.pop("hooks", None)
    with open(p, "w") as f: json.dump(s, f, indent=2)
PY
# Codex hooks, the buddy command, and the CLAUDE.md / AGENTS.md section
/usr/bin/python3 - <<'PY'
import json, os, re
p = os.path.expanduser("~/.codex/hooks.json")
if os.path.exists(p):
    with open(p) as f: s = json.load(f)
    hooks = s.get("hooks", {})
    for ev in list(hooks):
        hooks[ev] = [g for g in hooks[ev] if not any("buddy-hook" in h.get("command", "") for h in g.get("hooks", []))]
        if not hooks[ev]: del hooks[ev]
    with open(p, "w") as f: json.dump(s, f, indent=2)
for f in ["~/.claude/CLAUDE.md", "~/.codex/AGENTS.md"]:
    f = os.path.expanduser(f)
    if os.path.exists(f):
        t = open(f).read()
        t = re.sub(r"\n?<!-- agent-buddy:start -->.*?<!-- agent-buddy:end -->\n?", "", t, flags=re.S)
        open(f, "w").write(t)
PY
for b in /opt/homebrew/bin/buddy "$HOME/.local/bin/buddy"; do grep -q agent-buddy "$b" 2>/dev/null && rm -f "$b"; done
echo "Agent Buddy removed."
