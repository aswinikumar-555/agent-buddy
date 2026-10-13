// buddy-hook: called by Claude Code hooks. Reads the hook JSON from stdin,
// keeps only the fields Agent Buddy needs, and appends one line to
// ~/.agent-buddy/events.jsonl.
//
// In remote mode (~/.agent-buddy/remote-mode exists and the app is alive),
// PermissionRequest and Stop hooks wait for an answer from the app
// (~/.agent-buddy/replies/<request_id>.json) and hand it back to Claude.
// If the app goes away, times out, or the user picks "Terminal", the hook exits
// with no output so Claude falls back to its normal terminal behavior.
//
// Chat: messages the user posts from the app are queued in
// ~/.agent-buddy/inbox/<session_id>.jsonl and delivered at the next
// PostToolUse / UserPromptSubmit (as additionalContext) or Stop (as a block
// reason, so Claude keeps going and reads it).
// Also used by Codex (~/.codex/hooks.json): its events are tagged "agent": "codex",
// and get the same remote-mode answers and chat delivery (Codex reads the same replies).
//
// `buddy say "<message>" [--urgent]`: any agent or script can put a message on
// the buddy (the `buddy` command is a tiny wrapper around this binary).
// Never exits non-zero, so it can never break Claude.
import Foundation

let dir = NSHomeDirectory() + "/.agent-buddy"
let maxWait: TimeInterval = 570 // hook timeout in settings.json is 600s

func append(_ dict: [String: Any]) {
    var d = dict
    d["ts"] = Date().timeIntervalSince1970
    guard var line = try? JSONSerialization.data(withJSONObject: d) else { return }
    line.append(0x0A)
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let fd = open(dir + "/events.jsonl", O_WRONLY | O_APPEND | O_CREAT, 0o600)
    if fd >= 0 {
        line.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }
}

func appAlive() -> Bool {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: dir + "/heartbeat"),
          let mtime = attrs[.modificationDate] as? Date else { return false }
    return Date().timeIntervalSince(mtime) < 15
}

func respond(_ obj: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        FileHandle.standardOutput.write(data)
    }
}

func truncate(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n)) + "…" : s }

/// Short, human-readable description of what a tool wants to do.
func summarize(tool: String, input: [String: Any]) -> String {
    for key in ["command", "file_path", "notebook_path", "url", "pattern", "query", "prompt", "description"] {
        if let v = input[key] as? String, !v.isEmpty {
            let desc = (key != "description" ? input["description"] as? String : nil).map { "\n— \($0)" } ?? ""
            return truncate(v, 600) + desc
        }
    }
    let json = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
        .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    return truncate(json, 600)
}

/// Last assistant text from the transcript (its tail only), for Claude Code
/// versions that don't send last_assistant_message.
func lastAssistantText(transcript: String) -> String {
    guard let fh = FileHandle(forReadingAtPath: transcript) else { return "" }
    defer { try? fh.close() }
    let size = (try? fh.seekToEnd()) ?? 0
    try? fh.seek(toOffset: size > 524_288 ? size - 524_288 : 0)
    guard let data = try? fh.readToEnd(), let text = String(data: data, encoding: .utf8) else { return "" }
    for line in text.split(separator: "\n").reversed() {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]] else { continue }
        let parts = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        if !parts.isEmpty { return parts.joined(separator: "\n") }
    }
    return ""
}

/// Atomically takes all queued chat messages for a session.
func takeInbox(_ sessionId: String) -> [[String: Any]] {
    guard !sessionId.isEmpty, !sessionId.contains("/") else { return [] }
    let path = "\(dir)/inbox/\(sessionId).jsonl"
    let taken = path + ".\(getpid()).taking"
    guard rename(path, taken) == 0 else { return [] }
    defer { unlink(taken) }
    guard let text = try? String(contentsOfFile: taken, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap {
        try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
    }
}

func inboxText(_ messages: [[String: Any]]) -> String {
    let body = messages.compactMap { $0["text"] as? String }.map { "> " + $0.replacingOccurrences(of: "\n", with: "\n> ") }
    return "The user sent you \(messages.count == 1 ? "a message" : "messages") from Agent Buddy (their desktop assistant) "
        + "while you were working:\n\n" + body.joined(separator: "\n\n")
        + "\n\nTake this into account, reply to it briefly, and continue."
}

func markDelivered(_ messages: [[String: Any]], _ sessionId: String) {
    append(["hook_event_name": "MessagesDelivered", "session_id": sessionId,
            "message_ids": messages.compactMap { $0["id"] as? String }])
}

/// The terminal device Claude is running in (hooks themselves have no tty,
/// so walk up the process tree). Lets the app type into that terminal tab.
func claudeTTY() -> String? {
    var pid = getppid()
    for _ in 0..<5 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "ppid=,tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        let parts = out.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard parts.count == 2, let ppid = Int32(parts[0]) else { return nil }
        if parts[1] != "??" { return "/dev/" + parts[1] }
        pid = ppid
    }
    return nil
}

// `buddy say "message" [--urgent]`
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "say" {
    let urgent = args.contains("--urgent")
    let message = args.dropFirst().filter { $0 != "--urgent" }.joined(separator: " ")
    guard !message.trimmingCharacters(in: .whitespaces).isEmpty else {
        FileHandle.standardError.write("usage: buddy say \"<message>\" [--urgent]\n".data(using: .utf8)!)
        exit(1)
    }
    append(["hook_event_name": "Say", "session_id": "", "message": truncate(message, 300), "urgent": urgent,
            "cwd": FileManager.default.currentDirectoryPath])
    exit(0)
}

// `buddy todo "<text>"`: adds a to-do to the buddy's list (Me tab).
if args.first == "todo" {
    let text = args.dropFirst().joined(separator: " ")
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
        FileHandle.standardError.write("usage: buddy todo \"<text>\"\n".data(using: .utf8)!)
        exit(1)
    }
    append(["hook_event_name": "Todo", "session_id": "", "message": truncate(text, 200),
            "cwd": FileManager.default.currentDirectoryPath])
    exit(0)
}

// Claude Code status line (`"statusLine": {"type": "command", "command": "~/.agent-buddy/buddy-hook statusline"}`):
// Claude passes your plan's usage limits here. Saved for the buddy, and printed as the status line.
if args.first == "statusline" {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    let model = (obj["model"] as? [String: Any])?["display_name"] as? String ?? ""
    var parts = model.isEmpty ? [] : [model]
    if let limits = obj["rate_limits"] as? [String: Any], !limits.isEmpty {
        let usage: [String: Any] = ["rate_limits": limits, "at": Date().timeIntervalSince1970]
        if let out = try? JSONSerialization.data(withJSONObject: usage) {
            try? out.write(to: URL(fileURLWithPath: dir + "/usage.json"), options: .atomic)
        }
        for (key, label) in [("five_hour", "5h"), ("seven_day", "week")] {
            if let pct = (limits[key] as? [String: Any])?["used_percentage"] as? Double {
                parts.append("\(label) \(Int(pct.rounded()))%")
            }
        }
    }
    print(parts.joined(separator: " · "))
    exit(0)
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let obj = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { exit(0) }
var event = obj["hook_event_name"] as? String ?? ""
let isCodex = (obj["transcript_path"] as? String ?? "").contains("/.codex/")
let remote = FileManager.default.fileExists(atPath: dir + "/remote-mode") && appAlive()

// Codex asking for approval outside remote mode: show it as "needs you".
if isCodex && event == "PermissionRequest" && !remote {
    let tool = obj["tool_name"] as? String ?? "a tool"
    let what = summarize(tool: tool, input: obj["tool_input"] as? [String: Any] ?? [:])
    append(["hook_event_name": "Notification", "session_id": "codex-" + (obj["session_id"] as? String ?? ""),
            "cwd": obj["cwd"] ?? "", "agent": "codex", "message": "wants to run: " + truncate(what, 160)])
    exit(0)
}
// PermissionRequest is only interesting when the app is going to answer it.
if event == "PermissionRequest" && !remote { exit(0) }

// About to run a shell command: tell the app if it touches production. Never blocks.
if event == "PreToolUse" {
    let input = obj["tool_input"] as? [String: Any] ?? [:]
    let command = (input["command"] as? String)
        ?? (input["command"] as? [String])?.joined(separator: " ")
        ?? (input["cmd"] as? String) ?? ""
    guard !command.isEmpty else { exit(0) }
    // Generic defaults (same as ProdGuard.defaultPatterns); "prodPatterns" in the config replaces them.
    var patterns = [
        "--profile[= ]+prod", "\\b(ENV|NODE_ENV|APP_ENV|RAILS_ENV|STAGE)=(prod|production)\\b",
        "git\\s+push\\b.*\\b(prod|production)\\b", "kubectl\\b.*--context[= ]\\S*prod",
    ]
    if let data = FileManager.default.contents(atPath: dir + "/config.json"),
       let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let custom = cfg["prodPatterns"] as? [String], !custom.isEmpty { patterns = custom }
    for p in patterns {
        guard let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
              re.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil else { continue }
        let sid = obj["session_id"] as? String ?? ""
        append(["hook_event_name": "ProdTouch", "session_id": isCodex ? "codex-" + sid : sid,
                "cwd": obj["cwd"] ?? "", "agent": isCodex ? "codex" : "claude", "command": truncate(command, 200)])
        break
    }
    exit(0)
}

var out: [String: Any] = [:]
for key in ["hook_event_name", "session_id", "cwd", "message", "notification_type", "tool_name", "agent_type", "agent_id", "transcript_path"] {
    if let v = obj[key] { out[key] = v }
}
if let prompt = obj["prompt"] as? String { out["prompt"] = truncate(prompt, 300) }
if isCodex {
    out["agent"] = "codex"
    out["session_id"] = "codex-" + (obj["session_id"] as? String ?? "") // never clashes with Claude ids
}
// What the agent said last: its one-line "done" summary in the buddy's bubble.
if event == "Stop" {
    var last = obj["last_assistant_message"] as? String ?? ""
    if last.isEmpty, !isCodex, let t = obj["transcript_path"] as? String { last = lastAssistantText(transcript: t) }
    if !last.isEmpty { out["last_message"] = truncate(last, 2000) }
}
if event == "UserPromptSubmit" || event == "Stop" {
    if let tty = claudeTTY() { out["tty"] = tty }
    let env = ProcessInfo.processInfo.environment
    if let term = env["TERM_PROGRAM"] { out["term"] = term }
    if env["HERDR_ENV"] == "1", let pane = env["HERDR_PANE_ID"] {
        out["herdr_pane"] = pane
        out["herdr_socket"] = env["HERDR_SOCKET_PATH"] ?? ""
        out["herdr_bin"] = env["HERDR_BIN_PATH"] ?? ""
    }
}

// Deliver queued chat messages to the main agent (never into a subagent).
let sessionId = (isCodex ? "codex-" : "") + (obj["session_id"] as? String ?? "")
let isSubagent = obj["agent_id"] != nil
if !isSubagent && ["PostToolUse", "UserPromptSubmit", "Stop"].contains(event) {
    let messages = takeInbox(sessionId)
    if !messages.isEmpty {
        append(out)
        if event == "Stop" {
            respond(["decision": "block", "reason": inboxText(messages)])
        } else {
            respond(["hookSpecificOutput": ["hookEventName": event, "additionalContext": inboxText(messages)]])
        }
        markDelivered(messages, sessionId)
        exit(0)
    }
}

let interactive = remote && (event == "PermissionRequest" || event == "Stop")
guard interactive else { append(out); exit(0) }

let requestId = UUID().uuidString
out["request_id"] = requestId
let toolName = obj["tool_name"] as? String ?? ""
let toolInput = obj["tool_input"] as? [String: Any] ?? [:]
if event == "PermissionRequest" {
    if toolName == "AskUserQuestion" {
        out["questions"] = toolInput["questions"] ?? []
    } else {
        out["summary"] = summarize(tool: toolName, input: toolInput)
    }
}
append(out)

let replyPath = "\(dir)/replies/\(requestId).json"
let deadline = Date().addingTimeInterval(maxWait)
while Date() < deadline && appAlive() {
    if event == "Stop" {
        let messages = takeInbox(sessionId)
        if !messages.isEmpty {
            respond(["decision": "block", "reason": inboxText(messages)])
            markDelivered(messages, sessionId)
            append(["hook_event_name": "RequestClosed", "request_id": requestId, "session_id": sessionId])
            exit(0)
        }
    }
    if let data = FileManager.default.contents(atPath: replyPath),
       let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        try? FileManager.default.removeItem(atPath: replyPath)
        let action = reply["action"] as? String ?? "release"
        let text = reply["text"] as? String ?? ""
        switch (event, action) {
        case ("PermissionRequest", "allow"):
            var decision: [String: Any] = ["behavior": "allow"]
            if toolName == "AskUserQuestion", let answers = reply["answers"] as? [String: Any] {
                var updated = toolInput
                updated["answers"] = answers
                decision["updatedInput"] = updated
            }
            respond(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
        case ("PermissionRequest", "deny"):
            respond(["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                            "decision": ["behavior": "deny",
                                                         "message": text.isEmpty ? "The user denied this from Agent Buddy." : text]]])
        case ("Stop", "reply") where !text.isEmpty:
            respond(["decision": "block", "reason": "The user replied (via Agent Buddy): \(text)"])
        default:
            break // "release": let Claude do its normal thing
        }
        append(["hook_event_name": "RequestClosed", "request_id": requestId, "session_id": sessionId])
        exit(0)
    }
    usleep(250_000)
}
append(["hook_event_name": "RequestClosed", "request_id": requestId, "session_id": sessionId])
exit(0)
