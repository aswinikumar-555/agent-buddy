// Chat with an agent: shows the session's conversation (read from its
// transcript) and lets the user post messages, which the hook delivers to the
// agent at its next step (see Sources/Hook/main.swift).
import AppKit
import SwiftUI

let inboxDir = buddyDir.appendingPathComponent("inbox")

struct ChatItem: Identifiable {
    let id: String
    let fromUser: Bool
    let text: String
    let date: Date
    var status: String? = nil // for messages sent from the bot: "queued" / "delivered"
}

/// A message the user posted from the bot.
struct SentMessage {
    let id: String
    let text: String
    let date: Date
    var delivered: Bool
    var via: String? = nil // "terminal" while being typed into the agent's terminal
}

/// Where an agent's interactive session lives, so an idle agent can be sent a
/// new prompt: a herdr pane (preferred) or a macOS Terminal tab.
struct TerminalTarget: Equatable {
    var herdrPane: String?
    var herdrSocket: String?
    var herdrBin: String?
    var tty: String?
    var term: String?

    init() {}

    init?(event e: [String: Any]) {
        herdrPane = e["herdr_pane"] as? String
        herdrSocket = e["herdr_socket"] as? String
        herdrBin = e["herdr_bin"] as? String
        tty = e["tty"] as? String
        term = e["term"] as? String
        if herdrPane == nil && !(term == "Apple_Terminal" && tty != nil) && !(term == "iTerm.app" && tty != nil) { return nil }
    }

    /// Submits text as a new prompt. Returns an error description, or nil on success.
    func submit(_ text: String) -> String? {
        if let pane = herdrPane { return Herdr.prompt(pane, text, socket: herdrSocket) }
        guard let tty else { return "no terminal" }
        // Terminal/iTerm submit on newline, so keep it to one line.
        let line = text.replacingOccurrences(of: "\n", with: " ")
        let script: [String]
        if term == "iTerm.app" {
            script = ["on run argv", "tell application \"iTerm2\"",
                      "repeat with w in windows", "repeat with t in tabs of w", "repeat with s in sessions of t",
                      "if tty of s is (item 1 of argv) then", "tell s to write text (item 2 of argv)", "return \"ok\"", "end if",
                      "end repeat", "end repeat", "end repeat", "end tell", "return \"notfound\"", "end run"]
        } else {
            script = ["on run argv", "tell application \"Terminal\"",
                      "repeat with w in windows", "repeat with t in tabs of w",
                      "if tty of t is (item 1 of argv) then", "do script (item 2 of argv) in t", "return \"ok\"", "end if",
                      "end repeat", "end repeat", "end tell", "return \"notfound\"", "end run"]
        }
        let (status, output) = runProcess("/usr/bin/osascript", script.flatMap { ["-e", $0] } + [tty, line], env: nil)
        if status == 0 && output.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" { return nil }
        return output.contains("notfound") ? "terminal tab not found" : oneLine(output, max: 80)
    }

    /// Brings the agent's pane/tab to the front.
    func focus() {
        if let pane = herdrPane { Herdr.focus(pane, socket: herdrSocket); return }
        guard let tty, term == "Apple_Terminal" else { DispatchQueue.main.async { activateTerminalApp() }; return }
        let script = ["on run argv", "tell application \"Terminal\"", "activate",
                      "repeat with w in windows", "repeat with t in tabs of w",
                      "if tty of t is (item 1 of argv) then", "set selected of t to true", "set index of w to 1", "end if",
                      "end repeat", "end repeat", "end tell", "end run"]
        _ = runProcess("/usr/bin/osascript", script.flatMap { ["-e", $0] } + [tty], env: nil)
    }
}

/// Reads the last part of a Claude Code transcript and returns the visible
/// conversation: user prompts and assistant text (no tool calls, no subagents).
func loadTranscript(_ path: String, limit: Int = 40) -> [ChatItem] {
    if path.contains("/.codex/") { return loadCodexTranscript(path, limit: limit) }
    guard let fh = FileHandle(forReadingAtPath: path) else { return [] }
    defer { try? fh.close() }
    let size = (try? fh.seekToEnd()) ?? 0
    let window: UInt64 = 1_500_000
    try? fh.seek(toOffset: size > window ? size - window : 0)
    guard let data = try? fh.readToEnd(), let text = String(data: data, encoding: .utf8) else { return [] }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var items: [ChatItem] = []
    for (n, line) in text.split(separator: "\n").enumerated() {
        guard let e = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let type = e["type"] as? String, type == "user" || type == "assistant",
              e["isSidechain"] as? Bool != true, e["isMeta"] as? Bool != true,
              let msg = e["message"] as? [String: Any] else { continue }

        var body = ""
        if let s = msg["content"] as? String {
            body = s
        } else if let parts = msg["content"] as? [[String: Any]] {
            body = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip empty turns, slash-command/system plumbing, and our own injected messages.
        if body.isEmpty || body.hasPrefix("<") || body.hasPrefix("Caveat:") || body.contains("(via Agent Buddy)") { continue }

        let date = (e["timestamp"] as? String).flatMap { iso.date(from: $0) } ?? Date.distantPast
        items.append(ChatItem(id: (e["uuid"] as? String) ?? "\(n)", fromUser: type == "user",
                              text: body.count > 2500 ? String(body.prefix(2500)) + "…" : body, date: date))
    }
    return Array(items.suffix(limit))
}

/// A Codex session file (~/.codex/sessions/…/rollout-….jsonl): your prompts and Codex's replies.
func loadCodexTranscript(_ path: String, limit: Int = 40) -> [ChatItem] {
    guard let fh = FileHandle(forReadingAtPath: path) else { return [] }
    defer { try? fh.close() }
    let size = (try? fh.seekToEnd()) ?? 0
    let window: UInt64 = 1_500_000
    try? fh.seek(toOffset: size > window ? size - window : 0)
    guard let data = try? fh.readToEnd(), let text = String(data: data, encoding: .utf8) else { return [] }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var items: [ChatItem] = []
    for (n, line) in text.split(separator: "\n").enumerated() {
        guard let e = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              e["type"] as? String == "response_item",
              let p = e["payload"] as? [String: Any], p["type"] as? String == "message",
              let role = p["role"] as? String, role == "user" || role == "assistant" else { continue }
        let parts = p["content"] as? [[String: Any]] ?? []
        var body = parts.compactMap { ["input_text", "output_text", "text"].contains($0["type"] as? String ?? "") ? $0["text"] as? String : nil }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip the instructions and environment Codex adds as "user" messages.
        if body.isEmpty || body.hasPrefix("<") || body.hasPrefix("# AGENTS.md") || body.contains("(via Agent Buddy)") { continue }
        if body.count > 2500 { body = String(body.prefix(2500)) + "…" }
        let date = (e["timestamp"] as? String).flatMap { iso.date(from: $0) } ?? Date.distantPast
        items.append(ChatItem(id: "\(n)", fromUser: role == "user", text: body, date: date))
    }
    return Array(items.suffix(limit))
}

struct ChatView: View {
    @ObservedObject var tracker: Tracker
    @ObservedObject var draft: CardDraft
    let sessionId: String

    private var task: AgentTask? { tracker.tasks.first { $0.id == sessionId } }

    var body: some View {
        let items = tracker.chatItems(for: sessionId)
        let pending = tracker.requests.filter { $0.sessionId == sessionId }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { withAnimation(.spring) { tracker.closeChat() } } label: {
                    Image(systemName: "chevron.left")
                }.buttonStyle(.borderless)
                Text(task?.project ?? "Agent").font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                stateChip
                Spacer()
                if let task, task.terminal != nil {
                    Button { tracker.jump(to: task) } label: { Image(systemName: "arrow.up.forward.app") }
                        .buttonStyle(.borderless).help("Jump to this agent's terminal")
                }
                Button { tracker.closePanel() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.borderless)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        if task?.usesScreen == true {
                            Text(tracker.screenText.isEmpty ? "Loading screen…" : tracker.screenText)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.85)))
                                .foregroundStyle(Color.white.opacity(0.9))
                        } else if items.isEmpty {
                            Text("No messages yet.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 20)
                        }
                        ForEach(items) { ChatBubble(item: $0) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .frame(height: max(120, tracker.panelHeight - (pending.isEmpty ? 90 : 210)))
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: items.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: tracker.screenText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }

            ForEach(pending) { RequestCard(request: $0, tracker: tracker, draft: $0.draft) }

            Text(hint).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .bottom, spacing: 6) {
                TextField("Message \(task?.project ?? "agent")…", text: $draft.text, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder).font(.system(size: 12))
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "paperplane.fill") }
                    .buttonStyle(ActionButtonStyle(color: Mood.idle.color))
                    .disabled(task == nil || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: tracker.panelWidth)
        .background(PanelBackground(radius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tracker.mood.color.opacity(0.6), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    private var stateChip: some View {
        let (label, color): (String, Color) = switch task?.state {
        case .working: ("working", Mood.working.color)
        case .waiting: ("needs you", Mood.waiting.color)
        case .done: ("idle", Mood.celebrating.color)
        case nil: ("ended", .secondary)
        }
        return Text(label).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var hint: String {
        guard let task else { return "This session has ended." }
        if task.usesScreen {
            switch task.state {
            case .working: return "Live view of its screen. Your message is sent as soon as it's idle."
            case .waiting: return "It's waiting on a prompt on its screen. Jump to it (↗) to answer. Messages are sent once it's idle."
            case .done: return "Live view of its screen. Your message is sent as a new prompt."
            }
        }
        if tracker.requests.contains(where: { $0.sessionId == sessionId && $0.isReply }) {
            return "The agent is waiting for you. Your message will continue it."
        }
        switch task.state {
        case .working: return "Your message reaches the agent at its next step."
        case .waiting: return "The agent is waiting on a prompt. Your message is delivered once it continues."
        case .done:
            return task.terminal != nil
                ? "The agent is idle. Your message is sent to its terminal as a new prompt."
                : "The agent is idle and I can't reach its terminal. Your message is delivered with your next prompt there."
        }
    }

    private func send() {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        tracker.sendChat(text, to: sessionId)
        draft.text = ""
    }
}

struct ChatBubble: View {
    let item: ChatItem
    var body: some View {
        HStack {
            if item.fromUser { Spacer(minLength: 40) }
            VStack(alignment: item.fromUser ? .trailing : .leading, spacing: 2) {
                Text(LocalizedStringKey(item.text))
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(item.fromUser ? Mood.idle.color.opacity(0.85) : Color.primary.opacity(0.07)))
                    .foregroundStyle(item.fromUser ? Color.white : Color.primary)
                if let status = item.status {
                    Label(status, systemImage: status == "delivered" ? "checkmark" : "clock")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            if !item.fromUser { Spacer(minLength: 40) }
        }
    }
}
