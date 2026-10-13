// herdr integration: herdr (terminal workspace manager for coding agents)
// knows every agent running in its panes, Claude or Codex, and its state
// (working / blocked / idle / done). Agent Buddy polls it so agents without
// Claude Code hooks (e.g. Codex) are tracked too, and uses it to prompt,
// read, and focus agents.
import AppKit
import Foundation

struct HerdrAgent {
    let pane: String
    let kind: String    // "claude", "codex", ...
    let status: String  // working, blocked, idle, done, unknown
    let cwd: String
    let title: String

    var project: String { cwd.split(separator: "/").last.map(String.init) ?? kind }
}

enum Herdr {
    static let bin = ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    static func run(_ args: [String], socket: String? = nil) -> (Int32, String) {
        guard let bin else { return (-1, "herdr not found") }
        var env = ProcessInfo.processInfo.environment
        if let socket, !socket.isEmpty { env["HERDR_SOCKET_PATH"] = socket }
        return runProcess(bin, args, env: env)
    }

    /// All agents herdr can see, or nil if herdr isn't installed/running.
    static func list() -> [HerdrAgent]? {
        let (status, out) = run(["agent", "list"])
        guard status == 0,
              let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
              let agents = (obj["result"] as? [String: Any])?["agents"] as? [[String: Any]] else { return nil }
        return agents.compactMap { a in
            guard let pane = a["pane_id"] as? String else { return nil }
            return HerdrAgent(pane: pane,
                              kind: a["agent"] as? String ?? "agent",
                              status: a["agent_status"] as? String ?? "unknown",
                              cwd: a["cwd"] as? String ?? "",
                              title: a["terminal_title_stripped"] as? String ?? "")
        }
    }

    /// What's currently on the agent's screen. Uses the visible viewport only, so
    /// it never scrolls the user's pane.
    static func screen(_ pane: String) -> String {
        let (status, out) = run(["agent", "read", pane, "--source", "visible"])
        guard status == 0 else { return "Couldn't read this agent's screen." }
        // herdr prints the screen as plain text (errors come back as JSON).
        var text = out
        if let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any] {
            if let t = ((obj["result"] as? [String: Any])?["read"] as? [String: Any])?["text"] as? String { text = t }
            else { return "Couldn't read this agent's screen." }
        }
        // Drop the blank rows TUIs pad the screen with.
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Submits a prompt. Returns an error description, or nil on success.
    static func prompt(_ pane: String, _ text: String, socket: String? = nil) -> String? {
        let (status, out) = run(["agent", "prompt", pane, text], socket: socket)
        if status == 0 { return nil }
        if out.contains("agent_blocked") { return "it's waiting on a prompt" }
        return oneLine(out, max: 80)
    }

    /// Focuses the agent's pane in herdr and brings the terminal app forward.
    static func focus(_ pane: String, socket: String? = nil) {
        _ = run(["agent", "focus", pane], socket: socket)
        DispatchQueue.main.async { activateTerminalApp() }
    }
}

func activateTerminalApp() {
    for id in ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"] {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate()
            return
        }
    }
}

func runProcess(_ path: String, _ args: [String], env: [String: String]?) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    if let env { p.environment = env }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    guard (try? p.run()) != nil else { return (-1, "couldn't run \(path)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}
