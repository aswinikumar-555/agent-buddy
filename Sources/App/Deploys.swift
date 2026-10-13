// GitHub deployment tracking: polls `gh run list` for workflow runs whose name
// looks like a deploy (configurable in ~/.agent-buddy/config.json).
import AppKit
import Foundation

struct DeployRun: Identifiable {
    let id: Int
    let repo: String
    let workflow: String
    let branch: String
    var status: String      // queued, in_progress, waiting, completed, ...
    var conclusion: String  // success, failure, cancelled, "" while running
    let created: Date
    var updated: Date
    let url: String

    var isActive: Bool { status != "completed" }
    var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
}

/// A reminder at a fixed time every day, e.g. {"time": "14:00", "title": "Lunch break", ...}.
struct DailyReminder: Codable, Equatable {
    var time: String     // "HH:mm", 24-hour, local time
    var title: String
    var message: String
    var emoji: String?
    var activity: String? // what the buddy acts out: "eat", "drink", "sleep"

    static let lunch = DailyReminder(time: "14:00", title: "Lunch break",
                                     message: "It's 2 PM. Step away and have lunch. Your agents will keep going.",
                                     emoji: "🍱", activity: "eat")
    static let sleep = DailyReminder(time: "23:00", title: "Time to sleep",
                                     message: "It's 11 PM. Wrap up, let your agents finish, and get some sleep.",
                                     emoji: "😴", activity: "sleep")
}

/// Notes for tomorrow (~/.agent-buddy/notes.json), newest last.
enum Notes {
    struct Note: Codable { let date: Date; let text: String }
    static var url = buddyDir.appendingPathComponent("notes.json")

    static func all() -> [Note] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Note].self, from: data)) ?? []
    }
    static func latest() -> Note? { all().last }
    static func save(_ text: String) {
        let notes = Array((all() + [Note(date: Date(), text: text)]).suffix(60))
        if let data = try? JSONEncoder().encode(notes) { try? data.write(to: url, options: .atomic) }
    }
}

struct DBTunnel: Codable, Equatable {
    var env: String
    var port: Int
}

struct BuddyConfig: Codable {
    var repos: [String]
    var deployWorkflowPattern: String
    var pollSeconds: Double
    var stuckWaitingMinutes: Double?
    var stuckQuietMinutes: Double?
    var breakMinutes: Double?
    var breakResetMinutes: Double?
    var stackRoots: [String]?
    var waterMinutes: Double?
    var dailyReminders: [DailyReminder]?
    var ecsClusters: [String]?
    var ecsRegion: String?
    var workdayEnd: String?   // "HH:mm": the buddy wraps up your day and offers a note for tomorrow
    var workHours: WorkHours?
    var sites: [SiteConfig]?
    var prodPatterns: [String]?  // read by the hook
    var prodEnvs: [String]?      // environment names that mean production (default prod, production)
    var dbTunnels: [DBTunnel]?   // local database tunnel ports to watch
    var gcpProjects: [GcpProject]?  // Google Cloud projects whose Cloud Run services to watch
    var autoRemote: Bool?           // remote mode on when you step away (default true)
    var autoRemoteMinutes: Double?  // how long away counts (default 5)
    var juggle: Int?                // agents at once before the buddy suggests finishing one (default 5)
    var meetings: Bool?             // meeting heads-up from the Calendar app (default true)
    var meetingHeadsUpMinutes: Double?  // how long before a meeting to warn you (default 5)
    var festivals: [Festival]?      // your own festivals and special days (added to the built-in ones)
    var features: [String: Bool]?   // turn features on or off: {"jira": false, "walking": true}
    var jira: JiraConfig?           // Jira site and email (the API token lives in your Keychain)
    var gitlab: GitLabConfig?       // GitLab projects (and host, if self-hosted), through the glab CLI

    static var url = buddyDir.appendingPathComponent("config.json")
    static let defaults = BuddyConfig(
        repos: [],   // e.g. ["your-org/your-repo"]: watched for deploys and your PRs
        deployWorkflowPattern: "(?i)deploy|promote|rollback|release",
        pollSeconds: 45,
        stuckWaitingMinutes: 10, stuckQuietMinutes: 20, breakMinutes: 90, breakResetMinutes: 5,
        waterMinutes: 60,
        dailyReminders: [DailyReminder.lunch, DailyReminder.sleep],
        ecsClusters: [], ecsRegion: "us-east-1")   // e.g. ["myapp-staging", "myapp-prod"]

    static func load() -> BuddyConfig {
        guard let data = try? Data(contentsOf: url) else {
            // First run: write the defaults so there's a file to edit.
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            try? enc.encode(defaults).write(to: url)
            return defaults
        }
        do {
            return try JSONDecoder().decode(BuddyConfig.self, from: data)
        } catch {
            // Never overwrite a config with a mistake in it: run on defaults and say why.
            NSLog("Agent Buddy: ~/.agent-buddy/config.json has an error, using defaults: \(error)")
            configError = "Your ~/.agent-buddy/config.json has an error, so I'm using defaults: \(error.localizedDescription)"
            return defaults
        }
    }
    static var configError: String?
}

final class DeployWatcher {
    var onUpdate: (String, [DeployRun]) -> Void = { _, _ in }
    private let config: BuddyConfig
    private let pattern: NSRegularExpression?
    private let queue = DispatchQueue(label: "agent-buddy.deploys")
    private let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    private var timer: Timer?

    init(config: BuddyConfig) {
        self.config = config
        pattern = try? NSRegularExpression(pattern: config.deployWorkflowPattern)
    }

    func start() {
        guard gh != nil, !config.repos.isEmpty else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: max(15, config.pollSeconds), repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard let gh else { return }
        for repo in config.repos {
            queue.async { [self] in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: gh)
                p.arguments = ["run", "list", "-R", repo, "-L", "50", "--json",
                               "databaseId,workflowName,headBranch,status,conclusion,createdAt,updatedAt,url"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                guard (try? p.run()) != nil else { return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard p.terminationStatus == 0,
                      let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

                let iso = ISO8601DateFormatter()
                let runs: [DeployRun] = rows.compactMap { r in
                    guard let id = r["databaseId"] as? Int, let name = r["workflowName"] as? String,
                          let pattern, pattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
                    else { return nil }
                    return DeployRun(id: id, repo: repo, workflow: name,
                                     branch: r["headBranch"] as? String ?? "",
                                     status: r["status"] as? String ?? "",
                                     conclusion: r["conclusion"] as? String ?? "",
                                     created: iso.date(from: r["createdAt"] as? String ?? "") ?? Date(),
                                     updated: iso.date(from: r["updatedAt"] as? String ?? "") ?? Date(),
                                     url: r["url"] as? String ?? "")
                }
                DispatchQueue.main.async { self.onUpdate(repo, runs) }
            }
        }
    }
}
