// Connects Agent Buddy to Claude Code and Codex: the hook program, hooks, status
// line, the `buddy` command, a note for agents, and starting at login.
// `install.sh` runs it as `AgentBuddy --setup --launch-agent`; the downloaded app
// offers it on first launch. Safe to run again. Every file it changes outside
// ~/.agent-buddy gets a one-time backup next to it (.bak-agent-buddy).
import AppKit
import Foundation
import ServiceManagement

enum Setup {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    private static let home = NSHomeDirectory()
    private static let fm = FileManager.default

    /// The app was downloaded (not built by install.sh) and hasn't been connected yet.
    static var needed: Bool {
        Bundle.main.path(forResource: "buddy-hook", ofType: nil) != nil
            && UserDefaults.standard.string(forKey: "setupVersion") == nil
    }

    /// Asks first, from the downloaded app.
    static func offer() {
        let alert = NSAlert()
        alert.messageText = "Connect Agent Buddy to Claude Code and Codex?"
        alert.informativeText = """
        Agent Buddy adds its hooks to ~/.claude/settings.json and ~/.codex/hooks.json (your own hooks are kept, and a backup is saved), \
        sets Claude Code's status line if you don't have one, installs the `buddy` command, and starts at login.
        """
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Not now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let log = run(launchAgent: false)
        let done = NSAlert()
        done.messageText = "Agent Buddy is connected"
        done.informativeText = log.joined(separator: "\n") + "\n\nRestart any open Claude Code or Codex sessions so they pick up the hooks."
        done.runModal()
    }

    /// Does the setup; returns what it did, one line per step.
    @discardableResult
    static func run(launchAgent: Bool) -> [String] {
        var log: [String] = []
        let dir = home + "/.agent-buddy"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Config, the first time.
        if !fm.fileExists(atPath: dir + "/config.json"), let example = Bundle.main.path(forResource: "config.example", ofType: "json") {
            try? fm.copyItem(atPath: example, toPath: dir + "/config.json")
            log.append("Created ~/.agent-buddy/config.json")
        }

        // The hook program.
        let hook = dir + "/buddy-hook"
        if let bundled = Bundle.main.path(forResource: "buddy-hook", ofType: nil) {
            try? fm.removeItem(atPath: hook)
            try? fm.copyItem(atPath: bundled, toPath: hook)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook)
        }
        guard fm.isExecutableFile(atPath: hook) else { return log + ["⚠️ The hook program is missing (\(hook))."] }

        // Claude Code: hooks and status line.
        let claude = home + "/.claude/settings.json"
        guard var settings = readJSON(claude) else {
            return log + ["⚠️ ~/.claude/settings.json isn't valid JSON, so I left it alone. Fix it and run setup again."]
        }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for ev in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "PermissionRequest", "Stop", "SubagentStop", "SessionEnd"] {
            var handler: [String: Any] = ["type": "command", "command": hook]
            if ev == "PermissionRequest" || ev == "Stop" { handler["timeout"] = 600 } // may wait for your answer (remote mode)
            var entry: [String: Any] = ["hooks": [handler]]
            if ev == "PostToolUse" || ev == "PermissionRequest" { entry["matcher"] = "*" }
            if ev == "PreToolUse" { entry["matcher"] = "Bash" } // only shell commands are checked for production
            hooks[ev] = withoutOurs(hooks[ev]) + [entry]
        }
        settings["hooks"] = hooks
        let statusLine = (settings["statusLine"] as? [String: Any])?["command"] as? String
        if statusLine == nil || statusLine!.contains("buddy-hook") {
            settings["statusLine"] = ["type": "command", "command": hook + " statusline"]
        } else {
            log.append("You have your own status line, so Claude plan usage isn't shown. To add it, pipe its input into: \(hook) statusline")
        }
        if writeJSON(settings, to: claude) { log.append("Added the hooks to Claude Code (~/.claude/settings.json)") }

        // Codex hooks.
        if fm.fileExists(atPath: home + "/.codex") {
            let codex = home + "/.codex/hooks.json"
            if var file = readJSON(codex) {
            var ch = file["hooks"] as? [String: Any] ?? [:]
            for ev in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"] {
                let timeout = ["PermissionRequest", "Stop"].contains(ev) ? 600 : 5
                ch[ev] = withoutOurs(ch[ev]) + [["hooks": [["type": "command", "command": hook, "timeout": timeout]]]]
            }
            file["hooks"] = ch
            if writeJSON(file, to: codex) { log.append("Added the hooks to Codex (~/.codex/hooks.json). In Codex, choose Trust all when it asks.") }
            } else {
                log.append("⚠️ ~/.codex/hooks.json isn't valid JSON, so I left it alone.")
            }
        }

        // The `buddy` command.
        let binDir = fm.isWritableFile(atPath: "/opt/homebrew/bin") ? "/opt/homebrew/bin" : home + "/.local/bin"
        try? fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        let script = "#!/bin/sh\n# Agent Buddy: buddy say \"<message>\" [--urgent], buddy todo \"<text>\"\nexec \"$HOME/.agent-buddy/buddy-hook\" \"$@\"\n"
        if (try? script.write(toFile: binDir + "/buddy", atomically: true, encoding: .utf8)) != nil {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binDir + "/buddy")
            log.append("Installed the buddy command (\(binDir)/buddy)")
        }

        // When agents should use `buddy say`.
        let note = """

        <!-- agent-buddy:start -->
        ## Agent Buddy
        When you finish something I'm waiting on, need my decision, or are blocked on me,
        run `buddy say "<one short sentence>"` (add `--urgent` if I must act now).
        Under 20 words. No secrets. Not for routine progress.
        <!-- agent-buddy:end -->

        """
        for f in [home + "/.claude/CLAUDE.md", home + "/.codex/AGENTS.md"] where fm.fileExists(atPath: (f as NSString).deletingLastPathComponent) {
            let text = (try? String(contentsOfFile: f, encoding: .utf8)) ?? ""
            if !text.contains("agent-buddy:start") { try? (text + note).write(toFile: f, atomically: true, encoding: .utf8) }
        }

        // Start at login.
        if launchAgent {
            let plist = home + "/Library/LaunchAgents/io.github.agentbuddy.plist"
            let exe = Bundle.main.executablePath ?? ""
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>io.github.agentbuddy</string>
              <key>ProgramArguments</key><array><string>\(exe)</string></array>
              <key>RunAtLoad</key><true/>
              <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
            </dict></plist>
            """
            try? fm.createDirectory(atPath: home + "/Library/LaunchAgents", withIntermediateDirectories: true)
            try? xml.write(toFile: plist, atomically: true, encoding: .utf8)
        } else if (try? SMAppService.mainApp.register()) != nil {
            log.append("Agent Buddy will start at login")
        }

        UserDefaults.standard.set(version, forKey: "setupVersion")
        return log
    }

    /// Undoes `run`: hooks, status line, the `buddy` command, the agents' note, and the login item.
    /// (Your ~/.agent-buddy folder is removed by uninstall.sh, or by hand.)
    @discardableResult
    static func uninstall() -> [String] {
        var log: [String] = []
        for path in [home + "/.claude/settings.json", home + "/.codex/hooks.json"] {
            guard fm.fileExists(atPath: path), var file = readJSON(path) else { continue }
            var hooks = file["hooks"] as? [String: Any] ?? [:]
            for (ev, groups) in hooks {
                let kept = withoutOurs(groups)
                hooks[ev] = kept.isEmpty ? nil : kept
            }
            file["hooks"] = hooks.isEmpty ? nil : hooks
            if ((file["statusLine"] as? [String: Any])?["command"] as? String ?? "").contains("buddy-hook") { file["statusLine"] = nil }
            if writeJSON(file, to: path) { log.append("Removed the hooks from \(path.replacingOccurrences(of: home, with: "~"))") }
        }
        for b in ["/opt/homebrew/bin/buddy", home + "/.local/bin/buddy"] {
            if let t = try? String(contentsOfFile: b, encoding: .utf8), t.contains("agent-buddy") { try? fm.removeItem(atPath: b) }
        }
        for f in [home + "/.claude/CLAUDE.md", home + "/.codex/AGENTS.md"] {
            guard let t = try? String(contentsOfFile: f, encoding: .utf8) else { continue }
            let cleaned = t.replacingOccurrences(of: "\\n?<!-- agent-buddy:start -->[\\s\\S]*?<!-- agent-buddy:end -->\\n?",
                                                 with: "", options: .regularExpression)
            if cleaned != t { try? cleaned.write(toFile: f, atomically: true, encoding: .utf8) }
        }
        try? SMAppService.mainApp.unregister()
        UserDefaults.standard.removeObject(forKey: "setupVersion")
        log.append("Removed the buddy command, the note for agents, and the login item")
        return log
    }

    /// A hook event's groups, minus Agent Buddy's own (so running again doesn't add duplicates).
    private static func withoutOurs(_ groups: Any?) -> [Any] {
        ((groups as? [Any]) ?? []).filter { g in
            let hooks = (g as? [String: Any])?["hooks"] as? [[String: Any]] ?? []
            return !hooks.contains { ($0["command"] as? String ?? "").contains("buddy-hook") }
        }
    }

    /// Empty if the file doesn't exist yet; nil if it exists but isn't a JSON object (never overwrite that).
    private static func readJSON(_ path: String) -> [String: Any]? {
        guard let data = fm.contents(atPath: path) else { return [:] }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Writes pretty JSON, after a one-time backup of the original.
    private static func writeJSON(_ obj: [String: Any], to path: String) -> Bool {
        if fm.fileExists(atPath: path) && !fm.fileExists(atPath: path + ".bak-agent-buddy") {
            try? fm.copyItem(atPath: path, toPath: path + ".bak-agent-buddy")
        }
        try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return false }
        return fm.createFile(atPath: path, contents: data)
    }
}
