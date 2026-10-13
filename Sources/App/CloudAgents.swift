// Claude Code sessions that hooks don't see: background agents (`claude --bg`,
// listed by `claude agents --json`) and cloud sessions, which work on `claude/…`
// branches in your GitHub repos and open pull requests from them.
import AppKit
import Foundation

struct BackgroundAgent: Identifiable, Equatable {
    enum State { case working, waiting, idle, done }
    let id: String          // short id, for `claude attach <id>`
    let sessionId: String
    let name: String
    let cwd: String
    let state: State
    let waitingFor: String

    var project: String { cwd.split(separator: "/").last.map(String.init) ?? "agent" }
}

struct CloudBranch: Identifiable, Equatable {
    var id: String { "\(repo)/\(branch)" }
    let repo: String
    let branch: String
    let committed: Date
    let headline: String
    let prNumber: Int?
    let prTitle: String?
    let prState: String?    // OPEN, MERGED, CLOSED
    let url: URL?

    var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
    /// A commit in the last 10 minutes: probably still working.
    var active: Bool { Date().timeIntervalSince(committed) < 600 }
}

enum ClaudeAgents {
    static let bin = [NSHomeDirectory() + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Background sessions only (interactive ones report through the hooks).
    static func background() -> [BackgroundAgent]? {
        guard let bin else { return nil }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + NSHomeDirectory() + "/.local/bin"
        let (st, out) = runProcess(bin, ["agents", "--json", "--all"], env: env)
        guard st == 0, let start = out.firstIndex(of: "["),
              let rows = try? JSONSerialization.jsonObject(with: Data(out[start...].utf8)) as? [[String: Any]] else { return nil }
        return rows.compactMap { r in
            guard r["kind"] as? String == "background", let id = r["id"] as? String else { return nil }
            let status = r["status"] as? String ?? "", state = r["state"] as? String ?? ""
            let s: BackgroundAgent.State = status == "waiting" || state == "blocked" ? .waiting
                : status == "busy" ? .working
                : state == "done" ? .done : .idle
            return BackgroundAgent(id: id, sessionId: r["sessionId"] as? String ?? id, name: r["name"] as? String ?? id,
                                   cwd: r["cwd"] as? String ?? "", state: s,
                                   waitingFor: r["waitingFor"] as? String ?? "")
        }
    }

    /// `claude/…` branches with a commit in the last day, newest first.
    static func cloudBranches(repos: [String]) -> [CloudBranch] {
        guard let gh = PRWatcher.gh else { return [] }
        let query = """
        query($owner:String!,$name:String!){repository(owner:$owner,name:$name){refs(refPrefix:"refs/heads/claude/",first:100){nodes{name target{... on Commit{committedDate messageHeadline}} associatedPullRequests(first:1,orderBy:{field:CREATED_AT,direction:DESC}){nodes{number title state url}}}}}}
        """
        let iso = ISO8601DateFormatter()
        var out: [CloudBranch] = []
        for repo in repos {
            let parts = repo.split(separator: "/")
            guard parts.count == 2 else { continue }
            let (st, json) = runProcess(gh, ["api", "graphql", "-f", "owner=\(parts[0])", "-f", "name=\(parts[1])", "-f", "query=\(query)"], env: nil)
            guard st == 0, let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let refs = ((obj["data"] as? [String: Any])?["repository"] as? [String: Any])?["refs"] as? [String: Any],
                  let nodes = refs["nodes"] as? [[String: Any]] else { continue }
            for n in nodes {
                let target = n["target"] as? [String: Any] ?? [:]
                guard let name = n["name"] as? String, let date = iso.date(from: target["committedDate"] as? String ?? ""),
                      Date().timeIntervalSince(date) < 86_400 else { continue }
                let pr = ((n["associatedPullRequests"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first
                out.append(CloudBranch(repo: repo, branch: "claude/" + name, committed: date,
                                       headline: target["messageHeadline"] as? String ?? "",
                                       prNumber: pr?["number"] as? Int, prTitle: pr?["title"] as? String,
                                       prState: pr?["state"] as? String,
                                       url: URL(string: (pr?["url"] as? String) ?? "https://github.com/\(repo)/tree/claude/\(name)")))
            }
        }
        return out.sorted { $0.committed > $1.committed }
    }

    /// Opens a background session in a new Terminal window.
    static func attach(_ agent: BackgroundAgent) {
        let cmd = "cd \(shellQuote(agent.cwd)) && claude attach \(agent.id)"
        let script = ["tell application \"Terminal\"", "activate", "do script \"\(cmd.replacingOccurrences(of: "\"", with: "\\\""))\"", "end tell"]
        _ = runProcess("/usr/bin/osascript", script.flatMap { ["-e", $0] }, env: nil)
    }

    private static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
