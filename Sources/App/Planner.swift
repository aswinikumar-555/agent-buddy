// Your to-do list, Claude plan usage, the weekly timesheet, and pull request stats.
import Foundation

// MARK: - To-dos

/// One item on the to-do list (~/.agent-buddy/todos.json).
struct Todo: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var text: String
    var created = Date()
    var done: Date?
    var due: Date?          // when you want to do it: the buddy reminds you then
    var reminded: Bool?

    func isLate(_ now: Date) -> Bool { done == nil && (due.map { $0 < now } ?? false) }

    /// "5:30 PM", "Tomorrow 9:00 AM" or "Fri 9:00 AM".
    static func timeText(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = cal.isDateInToday(d) ? "h:mm a" : cal.isDateInTomorrow(d) ? "'Tomorrow' h:mm a" : "EEE d MMM, h:mm a"
        return f.string(from: d)
    }

    /// A time at the end of the text: "call Ravi at 5pm", "deploy tomorrow 9:30am",
    /// "standup notes at 14:30". Returns the text without it, and the time (today, or
    /// tomorrow if that time has already passed today).
    static func parseTime(_ text: String, now: Date = Date()) -> (String, Date?) {
        let pattern = #"(?i)\s*(?:\b(today|tomorrow|tmrw)\b\s*)?(?:\bat\s+|@\s*)?(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(m.range, in: text) else { return (text, nil) }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { String(text[$0]).lowercased() } }
        let day = group(1), ampm = group(4), minutes = group(3)
        let said = text[whole].lowercased()
        // Only a real time: "at 5", "5pm", "5:30", or with today/tomorrow. Not "fix bug 2".
        guard said.contains("at ") || said.contains("@") || ampm != nil || minutes != nil || day != nil else { return (text, nil) }
        guard var hour = Int(group(2) ?? ""), let minute = Int(minutes ?? "0"), minute < 60 else { return (text, nil) }
        if let ampm {
            guard (1...12).contains(hour) else { return (text, nil) }
            hour = hour % 12 + (ampm == "pm" ? 12 : 0)
        }
        guard hour < 24 else { return (text, nil) }
        let cal = Calendar.current
        var date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if day == "tomorrow" || day == "tmrw" || (day == nil && date <= now) {
            date = cal.date(byAdding: .day, value: 1, to: date) ?? date
        }
        let rest = String(text[..<whole.lowerBound]).trimmingCharacters(in: .whitespaces)
        return (rest.isEmpty ? text : rest, date)
    }
}

enum Todos {
    static var url = buddyDir.appendingPathComponent("todos.json")

    static func load() -> [Todo] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Todo].self, from: data)) ?? []
    }

    static func save(_ list: [Todo]) {
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Claude plan usage

/// How much of your Claude plan's 5-hour and weekly limits you've used. Claude Code
/// passes this to its status line, and `buddy-hook statusline` saves it to usage.json.
struct ClaudeUsage: Equatable {
    struct Window: Equatable {
        let percent: Double
        let resets: Date?
    }
    var fiveHour: Window?
    var week: Window?
    var at: Date

    static var url = buddyDir.appendingPathComponent("usage.json")

    static func load() -> ClaudeUsage? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = obj["rate_limits"] as? [String: Any] else { return nil }
        let at = Date(timeIntervalSince1970: obj["at"] as? Double ?? 0)
        func window(_ key: String) -> Window? {
            guard let w = limits[key] as? [String: Any], let pct = w["used_percentage"] as? Double else { return nil }
            let resets = date(w["resets_at"])
            // Past its reset time, the window has started over.
            if let resets, resets < Date() { return Window(percent: 0, resets: nil) }
            return Window(percent: pct, resets: resets)
        }
        return ClaudeUsage(fiveHour: window("five_hour"), week: window("seven_day"), at: at)
    }

    /// Unix seconds, milliseconds, or an ISO 8601 string.
    private static func date(_ v: Any?) -> Date? {
        if let n = v as? Double { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        if let s = v as? String { return ISO8601DateFormatter().date(from: s) ?? Double(s).map { Date(timeIntervalSince1970: $0) } }
        return nil
    }
}

// MARK: - Timesheet

/// Time per project for one day, from the buddy's day logs: your focus (the project
/// you last gave an agent a prompt in, or a meeting) and the time agents spent working.
struct TimesheetDay: Identifiable {
    var id: String { day }
    let day: String
    let date: Date
    let keyboard: Double
    let projects: [(name: String, seconds: Double)]

    var total: Double { projects.reduce(0) { $0 + $1.seconds } }
}

enum Timesheet {
    /// Monday to Sunday of the week containing `date`.
    static func week(of date: Date) -> [TimesheetDay] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let start = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: start), d <= date else { return nil }
            return day(DayLog.load(d), date: d)
        }
    }

    static func day(_ log: DayLog, date: Date) -> TimesheetDay {
        let focus = log.focusSeconds ?? [:]
        // Older logs have no focus time: fall back to agent time.
        let source = focus.isEmpty ? log.agentSeconds : focus
        let projects = source.filter { $0.value >= 60 }.sorted { $0.value > $1.value }.map { (name: $0.key, seconds: $0.value) }
        return TimesheetDay(day: log.day, date: date, keyboard: log.activeSeconds, projects: projects)
    }

    /// Hours, rounded to the quarter hour: "1.25".
    static func hours(_ s: Double) -> String {
        let h = (s / 900).rounded() / 4
        return h == h.rounded() ? String(Int(h)) : String(format: "%.2f", h)
    }

    /// Tab-separated, so it pastes into a spreadsheet: one row per day and project.
    static func text(_ days: [TimesheetDay]) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE yyyy-MM-dd"
        var rows = ["Date\tProject\tHours"]
        for d in days where !d.projects.isEmpty {
            for p in d.projects { rows.append("\(f.string(from: d.date))\t\(p.name)\t\(hours(p.seconds))") }
        }
        var totals: [String: Double] = [:]
        for d in days { for p in d.projects { totals[p.name, default: 0] += p.seconds } }
        if !totals.isEmpty {
            rows.append("")
            for (name, s) in totals.sorted(by: { $0.value > $1.value }) { rows.append("Week\t\(name)\t\(hours(s))") }
        }
        return rows.joined(separator: "\n")
    }
}

// MARK: - Pull request stats

/// The last 7 days of pull requests in your repos: yours, and every account's merged and opened counts.
struct PRStats: Equatable {
    struct Person: Equatable, Identifiable {
        var id: String { login }
        let login: String
        var merged: Int
        var opened = 0
    }
    var me = ""
    var merged = 0
    var opened = 0
    var reviewed = 0
    var mergeHours: Double?     // median time from opening to merging your PRs
    var board: [Person] = []
    var at = Date()

    var myRank: Int? { board.firstIndex { $0.login == me }.map { $0 + 1 } }

    /// Everyone with a merged or opened PR, most merged first.
    static func board(merged: [String: Int], opened: [String: Int]) -> [Person] {
        Set(merged.keys).union(opened.keys)
            .map { Person(login: $0, merged: merged[$0] ?? 0, opened: opened[$0] ?? 0) }
            .sorted { ($0.merged, $0.opened, $1.login) > ($1.merged, $1.opened, $0.login) }
    }

    /// GitHub (repos) and GitLab (projects) together; your GitLab username counts as you.
    static func fetch(repos: [String], gitlab: GitLabConfig?) -> PRStats? {
        let fromGitHub = repos.isEmpty && gitlab != nil ? nil : fetchGitHub(repos: repos)
        guard let lab = gitlab.flatMap({ GitLab.stats($0) }) else { return fromGitHub }
        var s = fromGitHub ?? PRStats(me: lab.me)
        var merged = Dictionary(uniqueKeysWithValues: s.board.map { ($0.login, $0.merged) })
        var opened = Dictionary(uniqueKeysWithValues: s.board.map { ($0.login, $0.opened) })
        if fromGitHub == nil { merged = [:]; opened = [:] }
        for (who, n) in lab.merged { merged[who == lab.me ? s.me : who, default: 0] += n }
        for (who, n) in lab.openedBy { opened[who == lab.me ? s.me : who, default: 0] += n }
        s.merged += lab.merged[lab.me] ?? 0
        s.opened += lab.opened
        s.reviewed += lab.reviewed
        if !lab.hours.isEmpty {
            let all = (s.mergeHours.map { [$0] } ?? []) + lab.hours
            s.mergeHours = all.sorted()[all.count / 2]
        }
        s.board = board(merged: merged, opened: opened)
        return s
    }

    private static func fetchGitHub(repos: [String]) -> PRStats? {
        guard let gh = PRWatcher.gh else { return nil }
        func json(_ args: [String]) -> [[String: Any]]? {
            let (st, out) = runProcess(gh, args, env: nil)
            guard st == 0 else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]]
        }
        let (st, login) = runProcess(gh, ["api", "user", "--jq", ".login"], env: nil)
        guard st == 0 else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let since = ">=" + f.string(from: Date().addingTimeInterval(-7 * 86_400))
        // Every repo of the owners in `repos` (e.g. the whole org), not just the listed ones.
        let owners = repos.compactMap { $0.split(separator: "/").first.map(String.init) }
        let scope = Array(Set(owners)).sorted().flatMap { ["--owner", $0] }
        // One search per day: GitHub returns at most 1000 results per search, and a busy org passes that in a week.
        let days = (0...7).map { f.string(from: Date().addingTimeInterval(-Double($0) * 86_400)) }
        func everyone(_ field: String, _ fields: String) -> [[String: Any]] {
            days.flatMap { json(["search", "prs"] + scope + [field, $0, "--limit", "1000", "--json", fields]) ?? [] }
        }
        var s = PRStats(me: login.trimmingCharacters(in: .whitespacesAndNewlines))

        func isBot(_ author: [String: Any]) -> Bool {
            let who = author["login"] as? String ?? ""
            return who.isEmpty || author["type"] as? String == "Bot" || who.hasSuffix("[bot]") || who.hasPrefix("app/")
        }
        let iso = ISO8601DateFormatter()
        // Everyone's merged PRs (your orgs), or just yours when no repos are set.
        let mergedRows = repos.isEmpty
            ? json(["search", "prs", "--author", "@me", "--merged-at", since, "--limit", "300", "--json", "author,createdAt,closedAt"]) ?? []
            : everyone("--merged-at", "author,createdAt,closedAt")
        var counts: [String: Int] = [:]
        var hours: [Double] = []
        for r in mergedRows {
            let author = r["author"] as? [String: Any] ?? [:]
            if isBot(author) { continue }
            let who = author["login"] as? String ?? ""
            counts[who, default: 0] += 1
            if who == s.me, let a = iso.date(from: r["createdAt"] as? String ?? ""), let b = iso.date(from: r["closedAt"] as? String ?? "") {
                hours.append(b.timeIntervalSince(a) / 3600)
            }
        }
        s.merged = counts[s.me] ?? 0
        if !hours.isEmpty { s.mergeHours = hours.sorted()[hours.count / 2] }
        s.opened = json(["search", "prs"] + scope + ["--author", "@me", "--created", since, "--limit", "1000", "--json", "number"])?.count ?? 0
        if !repos.isEmpty {
            // Everyone's opened PRs, for the per-account table.
            var opened: [String: Int] = [:]
            for r in everyone("--created", "author") {
                let author = r["author"] as? [String: Any] ?? [:]
                if !isBot(author) { opened[author["login"] as? String ?? "", default: 0] += 1 }
            }
            s.board = board(merged: counts, opened: opened)
        }
        s.reviewed = (json(["search", "prs"] + scope + ["--reviewed-by", "@me", "--updated", since, "--limit", "1000", "--json", "author"]) ?? [])
            .filter { ($0["author"] as? [String: Any])?["login"] as? String != s.me }.count
        return s
    }
}
