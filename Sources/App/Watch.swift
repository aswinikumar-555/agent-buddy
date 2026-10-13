// Site health checks, production warnings, errors from local dev logs,
// work hours, and today's log for the end-of-day summary.
import AppKit
import Foundation

// MARK: - Site checks

struct SiteConfig: Codable, Equatable {
    var name: String
    var url: String
    var prod: Bool?
}

struct SiteStatus: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let url: String
    let prod: Bool
    var ok: Bool
    var code: Int        // 0 = no response
    var ms: Int
    var failures = 0     // consecutive
}

enum SiteChecker {
    /// None by default: list yours in the config, e.g.
    /// {"name": "staging", "url": "https://staging.example.com/api/health", "prod": false}
    static let defaults: [SiteConfig] = []

    /// One GET per site (blocking; call off the main thread). 2xx/3xx = up.
    static func check(_ sites: [SiteConfig]) -> [SiteStatus] {
        sites.map { s in
            guard let url = URL(string: s.url) else {
                return SiteStatus(name: s.name, url: s.url, prod: s.prod ?? false, ok: false, code: 0, ms: 0)
            }
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            req.setValue("AgentBuddy/1.0 (health check)", forHTTPHeaderField: "User-Agent")
            let sem = DispatchSemaphore(value: 0)
            var code = 0
            let start = Date()
            URLSession.shared.dataTask(with: req) { _, resp, _ in
                code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                sem.signal()
            }.resume()
            _ = sem.wait(timeout: .now() + 15)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return SiteStatus(name: s.name, url: s.url, prod: s.prod ?? false, ok: (200..<400).contains(code), code: code, ms: ms)
        }
    }
}

// MARK: - Production warning

struct ProdSignal: Identifiable, Equatable {
    var id: String { key }
    let key: String      // dedupe key
    let text: String     // what's touching production
    let at: Date
}

enum ProdGuard {
    /// What counts as production in a command (Bash run by an agent). Case-insensitive.
    /// Generic defaults; add your own (secret names, prod hostnames, …) as "prodPatterns" in the config.
    /// The hook (Sources/Hook/main.swift) uses the same list.
    static let defaultPatterns = [
        "--profile[= ]+prod", "\\b(ENV|NODE_ENV|APP_ENV|RAILS_ENV|STAGE)=(prod|production)\\b",
        "git\\s+push\\b.*\\b(prod|production)\\b", "kubectl\\b.*--context[= ]\\S*prod",
    ]
    /// Environment names that mean production ("prodEnvs" in the config).
    static var prodEnvs: Set<String> = ["prod", "production"]
}

// MARK: - Errors in local dev logs

struct LogError: Identifiable, Equatable {
    let id = UUID()
    let stack: String
    let service: String
    let line: String
    let path: String
    let at: Date
}

/// Follows the end of each running service's log and reports new error lines.
/// Each distinct error is reported once per 30 minutes, and each log at most
/// once per 2 minutes, so a crash loop doesn't flood you.
final class LogWatcher {
    private var offsets: [String: UInt64] = [:]
    private var seen: [String: Date] = [:]
    private var lastAlert: [String: Date] = [:]

    private let error = try! NSRegularExpression(
        pattern: "Traceback \\(most recent call last\\)|\\bERROR\\b|\\b[A-Z][A-Za-z]+Error\\b:|Exception:|UnhandledPromiseRejection|\\bFATAL\\b|\" 5\\d\\d |HTTP/1\\.[01]\" 5\\d\\d|500 Internal Server Error")
    private let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*m")

    func scan(_ logs: [(stack: String, service: String, path: String)]) -> [LogError] {
        var found: [LogError] = []
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 1800 }
        for log in logs {
            guard let fh = FileHandle(forReadingAtPath: log.path) else { continue }
            defer { try? fh.close() }
            let size = (try? fh.seekToEnd()) ?? 0
            guard let off = offsets[log.path] else { offsets[log.path] = size; continue } // skip history
            var start = off
            if size < off { start = 0 }                                // rotated or truncated
            if size - start > 262_144 { start = size - 262_144 }       // only the newest 256 KB
            offsets[log.path] = size
            guard size > start, now.timeIntervalSince(lastAlert[log.path] ?? .distantPast) > 120 else { continue }
            try? fh.seek(toOffset: start)
            guard let data = try? fh.readToEnd(), let text = String(data: data, encoding: .utf8) else { continue }
            // Keep indentation: a traceback's frames are indented, its exception line isn't.
            let lines = text.split(separator: "\n").map { strip(String($0)) }
            for (i, raw) in lines.enumerated() where matches(raw) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                var message = line
                if line.contains("Traceback") {
                    message = lines[(i + 1)...].first { !$0.hasPrefix(" ") && !$0.hasPrefix("\t") && !$0.isEmpty } ?? line
                }
                let sig = signature(message)
                guard seen[sig] == nil else { continue }
                seen[sig] = now
                lastAlert[log.path] = now
                found.append(LogError(stack: log.stack, service: log.service, line: oneLine(message, max: 220),
                                      path: log.path, at: now))
                break
            }
        }
        return found
    }

    private func matches(_ line: String) -> Bool {
        error.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private func strip(_ s: String) -> String {
        ansi.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    /// Same error, different numbers/ids/timestamps → same signature.
    private func signature(_ s: String) -> String {
        String(s.lowercased()
            .replacingOccurrences(of: "[0-9a-f]{8,}|\\d+", with: "#", options: .regularExpression)
            .prefix(140))
    }
}

// MARK: - Work hours

struct WorkHours: Codable, Equatable {
    var start: String   // "HH:mm"
    var end: String
    var days: [String]  // "Mon", "Tue", …

    static let defaults = WorkHours(start: "09:30", end: "20:00", days: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])

    func contains(_ date: Date) -> Bool {
        let cal = Calendar.current
        let day = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][cal.component(.weekday, from: date) - 1]
        guard days.contains(day) else { return false }
        let minutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        return minutes >= Self.minutes(start) && minutes < Self.minutes(end)
    }

    static func minutes(_ hhmm: String) -> Int {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 0
    }
}

// MARK: - Today's log (end-of-day summary)

struct DayLog: Codable {
    struct Entry: Codable { let project: String; let text: String; let at: Date }
    var day: String
    var agentsDone: [Entry] = []
    var prsMerged: [Entry] = []
    var deploys: [Entry] = []
    var activeSeconds: Double = 0
    var agentSeconds: [String: Double] = [:]   // project → time agents spent working

    static func key(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func url(_ day: String) -> URL { buddyDir.appendingPathComponent("days/\(day).json") }

    static func load(_ date: Date) -> DayLog {
        let day = key(date)
        if let data = try? Data(contentsOf: url(day)), let log = try? JSONDecoder().decode(DayLog.self, from: data) { return log }
        return DayLog(day: day)
    }

    func save() {
        try? FileManager.default.createDirectory(at: buddyDir.appendingPathComponent("days"), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: DayLog.url(day), options: .atomic) }
    }

    /// Plain text, ready to paste into standup or Jira.
    func summary(title: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        var out = ["Today (\(f.string(from: title)))"]
        if activeSeconds > 60 { out.append("• At the keyboard: \(formatDuration(activeSeconds))") }
        if !agentsDone.isEmpty {
            out.append("• Agents finished \(agentsDone.count) task\(agentsDone.count == 1 ? "" : "s"):")
            for e in agentsDone.suffix(8) { out.append("   – \(e.project): \(e.text)") }
            if agentsDone.count > 8 { out.append("   – …and \(agentsDone.count - 8) more") }
        }
        if !prsMerged.isEmpty {
            out.append("• PRs merged:")
            for e in prsMerged { out.append("   – \(e.project) \(e.text)") }
        }
        if !deploys.isEmpty {
            out.append("• Deploys:")
            for e in deploys.suffix(8) { out.append("   – \(e.project): \(e.text)") }
        }
        let byProject = agentSeconds.filter { $0.value >= 60 }.sorted { $0.value > $1.value }
        if !byProject.isEmpty {
            out.append("• Agent time: " + byProject.map { "\($0.key) \(formatDuration($0.value))" }.joined(separator: ", "))
        }
        if out.count == 1 { out.append("• Nothing recorded yet.") }
        return out.joined(separator: "\n")
    }
}
