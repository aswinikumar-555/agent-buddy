// Smaller helpers: the agent's one-line "done" summary, your GitHub pull
// requests, disk space / stale worktrees / huge logs, and microphone use.
import AppKit
import CoreAudio
import Foundation

// MARK: - "Done" summary

/// The first real sentence of what the agent said last, for the bubble:
/// skips headings, code, tables and list markers, and drops markdown.
func doneSummary(_ text: String, max: Int = 150) -> String {
    var inCode = false
    for raw in text.split(separator: "\n") {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("```") { inCode.toggle(); continue }
        if inCode || line.isEmpty || line.hasPrefix("#") || line.hasPrefix("|") || line.hasPrefix(">") || line.hasPrefix("{") { continue }
        if let r = line.range(of: "^([-*•]|\\d+[.)])\\s+", options: .regularExpression) { line.removeSubrange(r) }
        line = line.replacingOccurrences(of: "\\*\\*|__|`", with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        guard line.count > 3 else { continue }
        // First sentence, unless that's too short to say anything.
        if let end = line.range(of: "(?<=[.!?])\\s", options: .regularExpression),
           line.distance(from: line.startIndex, to: end.lowerBound) > 25 {
            line = String(line[..<end.lowerBound])
        }
        return line.count > max ? String(line.prefix(max)) + "…" : line
    }
    return ""
}

// MARK: - Pull requests

struct PullRequest: Identifiable, Equatable {
    enum Checks { case passing, failing, pending, none }
    var id: String { "\(repo)#\(number)" }
    let repo: String
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let review: String     // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, ""
    let mergeable: String  // MERGEABLE, CONFLICTING, UNKNOWN
    let checks: Checks
    var headRef = ""
    var ciError: String? = nil   // first error line of the newest failed CI run
    var agentId: String? = nil   // a local agent working on this PR's branch
    var host = "github"          // or "gitlab" (a merge request)

    var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
    /// Checks green, no conflicts, and approved (or the repo doesn't require a review).
    var readyToMerge: Bool {
        !isDraft && checks == .passing && mergeable == "MERGEABLE" && (review == "APPROVED" || review.isEmpty)
    }
}

enum PRWatcher {
    static let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }

    private static func ghJSON(_ args: [String]) -> Any? {
        guard let gh else { return nil }
        let (st, out) = runProcess(gh, args, env: nil)
        guard st == 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(out.utf8))
    }

    /// Your open PRs in the given repos.
    static func mine(repos: [String]) -> [PullRequest]? {
        guard gh != nil else { return nil }
        var all: [PullRequest] = []
        for repo in repos {
            guard let rows = ghJSON(["pr", "list", "-R", repo, "--author", "@me", "--state", "open", "--limit", "30", "--json",
                                     "number,title,url,isDraft,reviewDecision,mergeable,statusCheckRollup,headRefName"]) as? [[String: Any]]
            else { continue }
            all += rows.map { r in
                PullRequest(repo: repo, number: r["number"] as? Int ?? 0, title: r["title"] as? String ?? "",
                            url: r["url"] as? String ?? "", isDraft: r["isDraft"] as? Bool ?? false,
                            review: r["reviewDecision"] as? String ?? "", mergeable: r["mergeable"] as? String ?? "",
                            checks: checks(r["statusCheckRollup"] as? [[String: Any]] ?? []),
                            headRef: r["headRefName"] as? String ?? "")
            }
        }
        return all
    }

    /// Open PRs waiting for your review, anywhere on GitHub.
    static func reviewRequests() -> [PullRequest] {
        guard let rows = ghJSON(["search", "prs", "--review-requested=@me", "--state=open", "--limit", "20",
                                 "--json", "number,title,url,repository,isDraft"]) as? [[String: Any]] else { return [] }
        return rows.map { r in
            PullRequest(repo: (r["repository"] as? [String: Any])?["nameWithOwner"] as? String ?? "",
                        number: r["number"] as? Int ?? 0, title: r["title"] as? String ?? "", url: r["url"] as? String ?? "",
                        isDraft: r["isDraft"] as? Bool ?? false, review: "", mergeable: "", checks: .none)
        }
    }

    private static var ciCache: [String: (error: String?, at: Date)] = [:]

    /// The first error line from the newest failed CI run on the PR's branch (cached 10 min).
    static func ciError(_ pr: PullRequest) -> String? {
        if let c = ciCache[pr.id], Date().timeIntervalSince(c.at) < 600 { return c.error }
        var found: String?
        if let runs = ghJSON(["run", "list", "-R", pr.repo, "--branch", pr.headRef, "--status", "failure", "-L", "1",
                              "--json", "databaseId,workflowName"]) as? [[String: Any]],
           let run = runs.first, let id = run["databaseId"] as? Int, let gh {
            let (_, log) = runProcess(gh, ["run", "view", String(id), "-R", pr.repo, "--log-failed"], env: nil)
            let workflow = run["workflowName"] as? String ?? "CI"
            for line in log.split(separator: "\n") {
                // Lines look like "job\tstep\t2026-…Z ##[error]message"
                guard let r = line.range(of: "##[error]") else { continue }
                let msg = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if msg.isEmpty || msg.hasPrefix("Process completed with exit code") { continue }
                found = "\(workflow): " + (msg.count > 200 ? String(msg.prefix(200)) + "…" : msg)
                break
            }
            if found == nil, log.contains("##[error]") { found = "\(workflow) failed (see the run's log)" }
        }
        ciCache[pr.id] = (found, Date())
        return found
    }

    /// The git branch each folder is on (for linking PRs to the agents working on them).
    static func branches(of dirs: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for dir in Set(dirs) {
            let (st, b) = runProcess("/usr/bin/git", ["-C", dir, "rev-parse", "--abbrev-ref", "HEAD"], env: nil)
            let branch = b.trimmingCharacters(in: .whitespacesAndNewlines)
            if st == 0, !branch.isEmpty, branch != "HEAD" { out[dir] = branch }
        }
        return out
    }

    /// Was this PR merged (vs. closed)?
    static func wasMerged(_ pr: PullRequest) -> Bool {
        (ghJSON(["pr", "view", String(pr.number), "-R", pr.repo, "--json", "state"]) as? [String: Any])?["state"] as? String == "MERGED"
    }

    private static func checks(_ rollup: [[String: Any]]) -> PullRequest.Checks {
        if rollup.isEmpty { return .none }
        var pending = false
        for c in rollup {
            let conclusion = (c["conclusion"] as? String ?? "").uppercased()
            let state = (c["state"] as? String ?? "").uppercased()   // commit statuses
            let status = (c["status"] as? String ?? "").uppercased() // check runs
            if ["FAILURE", "TIMED_OUT", "ERROR", "STARTUP_FAILURE", "ACTION_REQUIRED"].contains(conclusion)
                || ["FAILURE", "ERROR"].contains(state) { return .failing }
            if (!status.isEmpty && status != "COMPLETED") || state == "PENDING" || state == "EXPECTED" { pending = true }
        }
        return pending ? .pending : .passing
    }
}

// MARK: - Housekeeping: disk, worktrees, huge logs (report only; never deletes)

struct Housekeeping: Equatable {
    struct Item: Identifiable, Equatable {
        var id: String { path }
        let path: String
        let detail: String
    }
    var freeGB: Double = 0
    var totalGB: Double = 0
    var bigLogs: [Item] = []
    var staleWorktrees: [Item] = []
    var prunable: [Item] = [] // repos whose git still lists worktrees whose folders are gone

    var lowDisk: Bool { freeGB > 0 && (freeGB < 15 || freeGB / max(totalGB, 1) < 0.08) }
    var hasNews: Bool { lowDisk || !bigLogs.isEmpty || !staleWorktrees.isEmpty || !prunable.isEmpty }

    static func scan(roots: [String]) -> Housekeeping {
        var h = Housekeeping()
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            h.freeGB = Double(v.volumeAvailableCapacityForImportantUsage ?? 0) / 1e9
            h.totalGB = Double(v.volumeTotalCapacity ?? 0) / 1e9
        }
        let fm = FileManager.default
        let dirs = roots.map { NSString(string: $0).expandingTildeInPath }.flatMap { root in
            ((try? fm.contentsOfDirectory(atPath: root)) ?? []).map { "\(root)/\($0)" }
        }
        let byteFmt = ByteCountFormatter()
        for dir in dirs {
            // Dev logs over 1 GB
            let logDir = "\(dir)/.dev-logs"
            for name in (try? fm.contentsOfDirectory(atPath: logDir)) ?? [] where name.hasSuffix(".log") {
                let path = "\(logDir)/\(name)"
                if let size = (try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value, size > 1_000_000_000 {
                    h.bigLogs.append(Item(path: path, detail: byteFmt.string(fromByteCount: size)))
                }
            }
            // Linked worktrees not touched for 14+ days (main checkouts have a .git directory)
            var isDir: ObjCBool = false
            let wtMeta = "\(dir)/.git/worktrees"
            guard fm.fileExists(atPath: wtMeta, isDirectory: &isDir), isDir.boolValue else { continue }
            var gone = 0
            for name in (try? fm.contentsOfDirectory(atPath: wtMeta)) ?? [] {
                let meta = "\(wtMeta)/\(name)"
                guard let gitdir = try? String(contentsOfFile: "\(meta)/gitdir", encoding: .utf8) else { continue }
                let path = (gitdir.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).deletingLastPathComponent
                if !fm.fileExists(atPath: path) { gone += 1; continue }
                let touched = ["index", "HEAD"].compactMap {
                    try? fm.attributesOfItem(atPath: "\(meta)/\($0)")[.modificationDate] as? Date
                }.max() ?? .distantPast
                let days = Int(Date().timeIntervalSince(touched) / 86_400)
                if days >= 14 {
                    h.staleWorktrees.append(Item(path: path, detail: "\(days) days untouched"))
                }
            }
            if gone > 0 {
                h.prunable.append(Item(path: dir, detail: "\(gone) entr\(gone == 1 ? "y" : "ies") for deleted folders · git worktree prune"))
            }
        }
        h.bigLogs.sort { $0.path < $1.path }
        h.staleWorktrees.sort { $0.path < $1.path }
        return h
    }
}

// MARK: - Microphone

/// True while any app is using the default microphone (a call or meeting):
/// break and water nudges wait until it's free.
func microphoneInUse() -> Bool {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
          device != 0 else { return false }
    var running: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
    return running != 0
}
