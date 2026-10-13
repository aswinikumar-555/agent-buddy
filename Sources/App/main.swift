// Agent Buddy: an always-on-top animated desktop character that tracks
// Claude Code agent tasks (via hooks -> ~/.agent-buddy/events.jsonl) and
// tells you when they finish or need your input.
import AppKit
import Combine
import SwiftUI

// MARK: - Model

enum TaskState { case working, waiting, done }

struct AgentTask: Identifiable {
    let id: String
    var project: String
    var prompt: String
    var state: TaskState
    var started: Date
    var finished: Date?
    var subagents = 0
    var transcript: String?
    var terminal: TerminalTarget?
    var kind = "claude"
    var summary: String? // the agent's one-line "done" summary
    var cwd: String?
    var lastActivity = Date()
    var waitingSince: Date?

    /// Seen only through herdr (no Claude Code hooks), e.g. Codex.
    var isHerdrOnly: Bool { id.hasPrefix("herdr:") }
    /// Chat shows its live screen (no readable transcript): herdr-only and Codex.
    var usesScreen: Bool { isHerdrOnly || kind == "codex" }
}

enum Mood { case idle, working, waiting, celebrating, stretching }

/// What clicking the speech bubble does.
enum BubbleAction { case session(String), url(URL), tab(PanelTab) }

/// A message an agent sent with `buddy say --urgent`.
struct AgentMessage: Identifiable {
    let id = UUID()
    let project: String
    let text: String
    let date: Date
}

struct AgentQuestion {
    let text: String
    let header: String
    let options: [String]
    let multi: Bool
}

/// What the user has typed/picked on a request card so far.
final class CardDraft: ObservableObject {
    @Published var text = ""
    @Published var picks: [Int: Set<String>] = [:]
    @Published var other: [Int: String] = [:]
}

/// Something an agent is waiting on, answered from the bot in remote mode.
struct PendingRequest: Identifiable {
    enum Kind {
        case permission(tool: String, summary: String)
        case questions([AgentQuestion])
        case reply(lastMessage: String)
    }
    let id: String
    let sessionId: String
    let project: String
    let kind: Kind
    let draft = CardDraft()

    var isReply: Bool { if case .reply = kind { return true } else { return false } }
}

extension Mood {
    var color: Color {
        switch self {
        case .idle: return Color(red: 0.36, green: 0.55, blue: 1.0)
        case .working: return Color(red: 1.0, green: 0.62, blue: 0.11)
        case .waiting: return Color(red: 1.0, green: 0.30, blue: 0.43)
        case .celebrating: return Color(red: 0.16, green: 0.80, blue: 0.53)
        case .stretching: return Color(red: 0.62, green: 0.45, blue: 1.0)
        }
    }
}

let buddyDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-buddy")
let eventsURL = buddyDir.appendingPathComponent("events.jsonl")
let repliesDir = buddyDir.appendingPathComponent("replies")
let remoteFlagURL = buddyDir.appendingPathComponent("remote-mode")
let heartbeatURL = buddyDir.appendingPathComponent("heartbeat")

func formatDuration(_ s: TimeInterval) -> String {
    let s = Int(max(0, s))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
}

func oneLine(_ s: String, max: Int = 80) -> String {
    let flat = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    return flat.count > max ? String(flat.prefix(max)) + "…" : flat
}

final class Tracker: ObservableObject {
    @Published var tasks: [AgentTask] = []
    @Published var deploys: [DeployRun] = []
    @Published var requests: [PendingRequest] = []
    @Published var chatSession: String?
    @Published private var chatHistory: [ChatItem] = []
    @Published private var sent: [String: [SentMessage]] = [:]
    let chatDraft = CardDraft()
    private var lastChatLoad = Date.distantPast
    private let chatQueue = DispatchQueue(label: "agent-buddy.chat")
    @Published var screenText = ""

    // herdr (Codex & other agents)
    private let herdrQueue = DispatchQueue(label: "agent-buddy.herdr")
    private var herdrSeeded = false
    private var herdrPolling = false
    private var lastHerdrPoll = Date.distantPast
    private var herdrPending: [String: [String]] = [:] // task id -> sent message ids waiting for it to be idle

    // Local dev stacks
    @Published var stacks: [DevStack] = []
    @Published var tunnels: [Tunnel] = []
    private let stackQueue = DispatchQueue(label: "agent-buddy.stacks")
    private lazy var stackMonitor: StackMonitor = {
        let m = StackMonitor(roots: projectRoots)
        m.tunnelPorts = (config.dbTunnels ?? []).map { ($0.env, $0.port) }
        return m
    }()
    /// Folders holding your projects (each one checked for a dev stack, big logs and old worktrees).
    var projectRoots: [String] { config.stackRoots ?? ["~/Developer", "~/code", "~/projects"] }
    private var stackPolling = false
    private var stackSeeded = false
    private var lastStackPoll = Date.distantPast

    // Cloud: AWS ECS services and Codex Cloud tasks
    @Published var ecs: [EcsService] = []
    @Published var ecsProblems: [String] = []
    @Published var codexCloud: [CodexCloudTask] = []
    @Published var codexSignedIn = true
    private var cloudPolling = false
    private var lastEcsPoll = Date.distantPast
    private var lastCodexPoll = Date.distantPast
    private var ecsSeeded = false
    private var codexSeeded = false
    private var ecsShortSince: [String: Date] = [:]   // service id → when running < desired started
    private var ecsAlerted: Set<String> = []
    var ecsRegion: String { config.ecsRegion ?? "us-east-2" }

    /// Panel sections the user collapsed, and ECS clusters they expanded (remembered).
    @Published var closedSections = Set(UserDefaults.standard.stringArray(forKey: "closedSections") ?? []) {
        didSet { UserDefaults.standard.set(Array(closedSections), forKey: "closedSections") }
    }
    @Published var openClusters = Set(UserDefaults.standard.stringArray(forKey: "openClusters") ?? []) {
        didSet { UserDefaults.standard.set(Array(openClusters), forKey: "openClusters") }
    }
    func toggle(_ key: String, in set: ReferenceWritableKeyPath<Tracker, Set<String>>) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if self[keyPath: set].contains(key) { self[keyPath: set].remove(key) } else { self[keyPath: set].insert(key) }
        }
    }

    // Google Cloud: gcloud login and Cloud Run services
    @Published var gcp: AwsStatus = .unknown
    @Published var cloudRun: [CloudRunService] = []
    @Published var gcpProblems: [String] = []
    private var gcpChecking = false
    private var lastGcpCheck = Date.distantPast
    private var gcpFastUntil = Date.distantPast
    private var cloudRunSeeded = false
    var gcpProjects: [GcpProject] { config.gcpProjects ?? [] }
    var cloudDownCount: Int { ecs.filter(\.isUnhealthy).count + cloudRun.filter(\.isUnhealthy).count }

    // AWS CLI login
    @Published var aws: AwsStatus = .unknown
    private var awsChecking = false
    private var lastAwsCheck = Date.distantPast
    private var awsFastUntil = Date.distantPast // check often right after "Log in"

    // Stuck-agent alerts
    private let config = BuddyConfig.load()
    private var nagged: [String: String] = [:] // task id -> last alert sent for its current condition
    private var lastStuckCheck = Date.distantPast

    // Water reminders
    @Published var waterDue = false
    @Published var waterOn = UserDefaults.standard.object(forKey: "waterReminders") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(waterOn, forKey: "waterReminders")
            nextWater = Date().addingTimeInterval(waterInterval)
            if !waterOn { waterDue = false }
        }
    }
    private lazy var nextWater = Date().addingTimeInterval(waterInterval)
    private var waterInterval: TimeInterval { (config.waterMinutes ?? 60) * 60 }

    // Site health
    @Published var sites: [SiteStatus] = []
    private var sitesPolling = false
    private var lastSitesPoll = Date.distantPast
    private var sitesFastUntil = Date.distantPast

    // Production warning: reasons, newest first
    @Published var prodCommands: [ProdSignal] = []
    var prodReasons: [String] {
        var r: [String] = []
        for t in tunnels where t.isProduction { r.append("Database tunnel to \(t.env) is open (port \(t.port))") }
        for st in stacks where ProdGuard.prodEnvs.contains(st.env) { r.append("Local \(st.name) is running against \(st.env)") }
        for c in prodCommands { r.append(c.text) }
        return r
    }
    var prodActive: Bool { !prodReasons.isEmpty }

    // Errors from local dev logs
    @Published var logErrors: [LogError] = []
    private let logWatcher = LogWatcher()

    // Work hours and today's log
    var workHours: WorkHours { config.workHours ?? WorkHours.defaults }
    var offDuty: Bool { !workHours.contains(Date()) }
    @Published var today = DayLog.load(Date())
    private var lastActiveTick = Date()
    private var lastIdle: TimeInterval = 0
    private var lastDaySave = Date()

    // Panel state
    @Published var panelTab: PanelTab = .agents
    /// Minimized panel: header, number tiles and status pills only (remembered).
    @Published var panelCompact = UserDefaults.standard.bool(forKey: "panelCompact") {
        didSet { UserDefaults.standard.set(panelCompact, forKey: "panelCompact") }
    }
    @Published var prodBannerOpen = false

    /// Panel size you set by dragging its top-left corner or edges (remembered).
    static let defaultPanelWidth: CGFloat = 400
    static let defaultPanelHeight: CGFloat = 360   // the scrolling list area
    @Published var panelWidth = UserDefaults.standard.object(forKey: "panelWidth") as? CGFloat ?? Tracker.defaultPanelWidth {
        didSet { UserDefaults.standard.set(panelWidth, forKey: "panelWidth") }
    }
    @Published var panelHeight = UserDefaults.standard.object(forKey: "panelHeight") as? CGFloat ?? Tracker.defaultPanelHeight {
        didSet { UserDefaults.standard.set(panelHeight, forKey: "panelHeight") }
    }
    var resizeStart: (mouse: NSPoint, width: CGFloat, height: CGFloat)?

    /// Remote mode switched on by the buddy because you stepped away (switches back off when you return).
    var autoRemoteOn = false
    private var lastJuggleNag = Date.distantPast

    /// Away for a few minutes while agents are running → remote mode on, so they wait for you
    /// here; back at the keyboard → off again, so you answer in the terminal.
    private func checkAutoRemote(idle: TimeInterval) {
        guard config.autoRemote ?? true else { return }
        let away = (config.autoRemoteMinutes ?? 5) * 60
        if !remoteMode && idle >= away && !runningAgents.isEmpty {
            autoRemoteOn = true
            remoteMode = true
        } else if autoRemoteOn && remoteMode && idle < 5 {
            autoRemoteOn = false
            remoteMode = false
        }
    }

    /// Too many agents at once is hard to follow: suggest finishing one (at most every 30 min).
    private func checkJuggling(_ now: Date) {
        let limit = config.juggle ?? 5
        let n = runningAgents.count
        guard n >= limit, now.timeIntervalSince(lastJuggleNag) > 1800 else { return }
        lastJuggleNag = now
        sayWork("🤹 You're running \(n) agents at once. Finish or check one before starting another?", for: 10)
    }

    /// Drag in progress: the panel is pinned bottom-right, so moving left widens it
    /// and moving up makes it taller.
    func resizePanel(width: Bool, height: Bool) {
        let m = NSEvent.mouseLocation
        if resizeStart == nil { resizeStart = (m, panelWidth, panelHeight) }
        guard let s = resizeStart else { return }
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        if width { panelWidth = min(max(s.width - (m.x - s.mouse.x), 320), min(900, screen.width - 40)).rounded() }
        if height { panelHeight = min(max(s.height + (m.y - s.mouse.y), 120), min(1100, screen.height - 320)).rounded() }
    }

    func endResize() { resizeStart = nil }

    func resetPanelSize() {
        withAnimation(.spring) { panelWidth = Tracker.defaultPanelWidth; panelHeight = Tracker.defaultPanelHeight }
    }
    /// From the minimized panel, a tile or pill opens the full panel on that tab.
    func show(_ tab: PanelTab) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            panelTab = tab
            panelCompact = false
        }
    }
    @Published var showAllDone = false
    @Published var showIdle = false

    var runningAgents: [AgentTask] { tasks.filter { $0.state == .working }.sorted { $0.started > $1.started } }
    var doneAgents: [AgentTask] {
        tasks.filter { $0.state == .done && !$0.isHerdrOnly }.sorted { ($0.finished ?? .distantPast) > ($1.finished ?? .distantPast) }
    }
    /// Agents waiting on you in their terminal (no card here to answer).
    var waitingAgents: [AgentTask] {
        tasks.filter { t in t.state == .waiting && !requests.contains { $0.sessionId == t.id } }
    }
    /// Everything in the panel's "Needs you" list.
    var panelNeedsYou: Int {
        requests.count + waitingAgents.count + urgentMessages.count
            + (breakDue ? 1 : 0) + (waterDue ? 1 : 0) + (dueReminder != nil ? 1 : 0)
            + (endOfDayDue ? 1 : 0) + (yesterdayNote != nil ? 1 : 0) + (napSummary != nil ? 1 : 0)
    }
    var breakMinutes: Double { config.breakMinutes ?? 90 }
    var waterMinutes: Double { config.waterMinutes ?? 60 }
    var nextWaterAt: Date { nextWater }
    var workdayEnd: String { config.workHours?.end ?? config.workdayEnd ?? "20:00" }
    var dailyReminderList: [DailyReminder] { config.dailyReminders ?? [DailyReminder.lunch, DailyReminder.sleep] }

    // Speech bubble click target
    @Published var bubbleAction: BubbleAction?

    // `buddy say --urgent` messages, kept until dismissed
    @Published var urgentMessages: [AgentMessage] = []

    // GitHub pull requests
    @Published var prs: [PullRequest] = []
    @Published var reviewPRs: [PullRequest] = []
    private var prPolling = false
    private var lastPRPoll = Date.distantPast
    private var prSeeded = false

    // Disk, huge logs, stale worktrees (every 10 min)
    @Published var housekeeping = Housekeeping()
    private var lastHousekeeping = Date.distantPast

    // Quiet time: a nap, or the microphone is on (a call)
    @Published var napUntil: Date?
    @Published var napSummary: [String]?
    private var napLog: [String] = []
    private var quietNow = false
    var napping: Bool { napUntil.map { Date() < $0 } ?? false }

    // End of the workday and tomorrow's note
    @Published var endOfDayDue = false
    @Published var yesterdayNote: String?
    let noteDraft = CardDraft()
    private var yawnUntil = Date.distantPast

    // What the buddy is acting out right now (eating, drinking, sleeping).
    @Published var activity: BuddyActivity?
    /// After "Going for lunch" / "Going to sleep": keep acting it out while you're
    /// away, until you're back at the keyboard (or `until` passes).
    private var activityHold: (activity: BuddyActivity, until: Date, sawAway: Bool)?
    private var drinkUntil = Date.distantPast

    // Daily reminders (2 PM lunch, 11 PM sleep)
    @Published var dueReminder: DailyReminder?
    private var reminderSnoozedUntil: [String: Date] = [:]

    // Break reminders
    @Published var breakDue = false
    private var workStreakStart: Date? = Date()
    private var lastBreakNag = Date.distantPast
    private var breaksSnoozedUntil = Date.distantPast
    @Published var remoteMode = FileManager.default.fileExists(atPath: remoteFlagURL.path) {
        didSet {
            if remoteMode {
                FileManager.default.createFile(atPath: remoteFlagURL.path, contents: nil)
                say("📡 Remote mode on: agents will wait for your answers here", for: 6)
            } else {
                try? FileManager.default.removeItem(at: remoteFlagURL)
                for r in requests { answer(r, ["action": "release"]) }
                say("💻 Remote mode off: answer in the terminal as usual", for: 5)
            }
        }
    }
    @Published var bubble: String?
    @Published var mood: Mood = .idle
    @Published var expanded = false
    /// Mac notifications (top-right banners) are off by default: everything is
    /// shown in the speech bubble above the buddy instead.
    @Published var macNotifications = UserDefaults.standard.bool(forKey: "macNotifications") {
        didSet { UserDefaults.standard.set(macNotifications, forKey: "macNotifications") }
    }
    /// Which 3D character sits on the desktop.
    @Published var character = BuddyCharacterKind(rawValue: UserDefaults.standard.string(forKey: "character") ?? "") ?? .nori {
        didSet { UserDefaults.standard.set(character.rawValue, forKey: "character") }
    }
    /// Robot size: 0.5 small, 0.75 medium, 1.0 large.
    @Published var scale = UserDefaults.standard.object(forKey: "scale") as? Double ?? 0.5 {
        didSet { UserDefaults.standard.set(scale, forKey: "scale") }
    }

    private var offset: UInt64 = 0
    private var celebrateUntil = Date.distantPast
    private var alertUntil = Date.distantPast
    private var seededRepos = Set<String>()
    private var deployWatcher: DeployWatcher?
    private var lastHeartbeat = Date.distantPast
    private var bubbleUntil = Date.distantPast
    private var timer: Timer?

    var activeCount: Int { tasks.filter { $0.state != .done }.count }

    /// Agents waiting on you (a request card or a blocked prompt).
    var needsYouCount: Int {
        Set(requests.map(\.sessionId)).union(tasks.filter { $0.state == .waiting }.map(\.id)).count
            + stacks.reduce(0) { $0 + $1.downCount }
            + (aws.isLoggedOut ? 1 : 0)
            + (gcp.isLoggedOut && !gcpProjects.isEmpty ? 1 : 0)
    }

    func resize(by step: Double) {
        withAnimation(.spring) { scale = min(1.2, max(0.3, (scale + step) * 10).rounded() / 10) }
    }

    func start() {
        if let envs = config.prodEnvs, !envs.isEmpty { ProdGuard.prodEnvs = Set(envs.map { $0.lowercased() }) }
        try? FileManager.default.createDirectory(at: buddyDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: repliesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: eventsURL.path) {
            FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        }
        // Skip history from before launch; keep the log from growing forever.
        let size = fileSize()
        if size > 5_000_000, let fh = try? FileHandle(forWritingTo: eventsURL) {
            try? fh.truncate(atOffset: 0)
            try? fh.close()
            offset = 0
        } else {
            offset = size
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        say(BuddyConfig.configError.map { "⚠️ \($0)" } ?? "Hi! I'm watching your agents 👀",
            for: BuddyConfig.configError == nil ? 5 : 20)

        let watcher = DeployWatcher(config: BuddyConfig.load())
        watcher.onUpdate = { [weak self] repo, runs in self?.mergeDeploys(repo: repo, runs: runs) }
        watcher.start()
        deployWatcher = watcher
    }

    // herdr-only agents stay listed while their pane exists.
    func clearDone() { tasks.removeAll { $0.state == .done && !$0.isHerdrOnly } }

    private func fileSize() -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: eventsURL.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func tick() {
        // Tells waiting hooks the app is alive; if it stops, they fall back to the terminal.
        if Date().timeIntervalSince(lastHeartbeat) > 4 {
            lastHeartbeat = Date()
            try? Data().write(to: heartbeatURL)
        }
        let size = fileSize()
        if size < offset { offset = 0 } // truncated externally
        if size > offset, let fh = try? FileHandle(forReadingFrom: eventsURL) {
            defer { try? fh.close() }
            try? fh.seek(toOffset: offset)
            let data = fh.readDataToEndOfFile()
            // Only consume complete lines; a partial write is picked up next tick.
            if let lastNewline = data.lastIndex(of: 0x0A) {
                let chunk = data[data.startIndex...lastNewline]
                offset += UInt64(chunk.count)
                for line in chunk.split(separator: 0x0A) {
                    if let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                        handle(obj)
                    }
                }
            }
        }

        let now = Date()
        let stale: (AgentTask) -> Bool = {
            $0.state == .done && !$0.isHerdrOnly && now.timeIntervalSince($0.finished ?? now) > 1800
        }
        if tasks.contains(where: stale) { tasks.removeAll(where: stale) }
        if chatSession != nil && now.timeIntervalSince(lastChatLoad) > 2 { refreshChat() }
        if !herdrPolling && now.timeIntervalSince(lastHerdrPoll) > 3 { pollHerdr() }
        if !stackPolling && now.timeIntervalSince(lastStackPoll) > 5 { pollStacks() }
        if !awsChecking && now.timeIntervalSince(lastAwsCheck) > (now < awsFastUntil ? 8 : 120) { checkAws() }
        if Gcp.bin != nil && !gcpChecking && now.timeIntervalSince(lastGcpCheck) > (now < gcpFastUntil ? 8 : 120) { checkGcp() }
        if !cloudPolling { pollCloudIfDue(now) }
        if !sitesPolling && now.timeIntervalSince(lastSitesPoll) > (now < sitesFastUntil ? 30 : 180) { pollSites() }
        if prodCommands.contains(where: { now.timeIntervalSince($0.at) > 600 }) {
            prodCommands.removeAll { now.timeIntervalSince($0.at) > 600 }
        }
        if now.timeIntervalSince(lastStuckCheck) > 10 { checkStuck(now); checkBreak(now) }
        if bubble != nil && now > bubbleUntil { withAnimation(.easeOut(duration: 0.3)) { bubble = nil; bubbleAction = nil } }
        if let until = napUntil, now >= until { wake() }
        if !prPolling && now.timeIntervalSince(lastPRPoll) > 120 { pollPRs() }
        if now.timeIntervalSince(lastHousekeeping) > 600 { scanHousekeeping() }

        let newMood: Mood = now < celebrateUntil ? .celebrating
            : now < alertUntil || !requests.isEmpty || tasks.contains { $0.state == .waiting }
                || stacks.contains { $0.downCount > 0 } ? .waiting
            : breakDue ? .stretching
            : tasks.contains { $0.state == .working } || deploys.contains { $0.isActive }
                || codexCloud.contains { $0.state == .working } ? .working
            : .idle
        if newMood != mood { mood = newMood }
    }

    private func handle(_ e: [String: Any]) {
        guard let event = e["hook_event_name"] as? String, let sid = e["session_id"] as? String else { return }
        let isCodex = e["agent"] as? String == "codex"
        let folder = ((e["cwd"] as? String) ?? "").split(separator: "/").last.map(String.init) ?? "agent"
        let project = isCodex ? "codex · \(folder)" : folder
        let idx = tasks.firstIndex { $0.id == sid }
        let requestId = e["request_id"] as? String

        switch event {
        case "ProdTouch":
            let cmd = (e["command"] as? String) ?? ""
            let signal = ProdSignal(key: sid + cmd, text: "\(project) ran: \(oneLine(cmd, max: 90))", at: Date())
            prodCommands.removeAll { $0.key == signal.key }
            prodCommands.insert(signal, at: 0)
            if prodCommands.count > 5 { prodCommands.removeLast() }
            alertUntil = Date().addingTimeInterval(5)
            say("⚠️ PROD: \(project) is touching production\n\(oneLine(cmd, max: 120))", for: 12, action: .session(sid))
            return

        case "Say":
            // `buddy say "…" [--urgent]` from an agent or script
            let text = (e["message"] as? String) ?? ""
            let task = tasks.first { $0.project == folder || $0.project.hasSuffix("· \(folder)") }
            let action = task.map { BubbleAction.session($0.id) }
            if e["urgent"] as? Bool == true {
                urgentMessages.append(AgentMessage(project: folder, text: text, date: Date()))
                alertUntil = Date().addingTimeInterval(5)
                say("📣 \(folder): \(text)", for: 20, action: action)
            } else {
                say("💬 \(folder): \(text)", for: 12, action: action)
            }
            return

        case "PermissionRequest":
            guard let rid = requestId else { return }
            let tool = (e["tool_name"] as? String) ?? "a tool"
            if let i = idx { tasks[i].state = .waiting }
            else { tasks.append(AgentTask(id: sid, project: project, prompt: "", state: .waiting, started: Date())) }
            if tool == "AskUserQuestion" {
                let qs = ((e["questions"] as? [[String: Any]]) ?? []).map { q in
                    AgentQuestion(text: q["question"] as? String ?? "",
                                  header: q["header"] as? String ?? "",
                                  options: ((q["options"] as? [[String: Any]]) ?? []).compactMap { $0["label"] as? String },
                                  multi: q["multiSelect"] as? Bool ?? false)
                }
                requests.append(PendingRequest(id: rid, sessionId: sid, project: project, kind: .questions(qs)))
                notify(title: "❓ \(project) has a question", body: qs.first?.text ?? "", sound: "Ping")
            } else {
                let summary = (e["summary"] as? String) ?? ""
                requests.append(PendingRequest(id: rid, sessionId: sid, project: project,
                                               kind: .permission(tool: tool, summary: summary)))
                notify(title: "🔐 \(project) wants to use \(tool)", body: oneLine(summary, max: 120), sound: "Ping")
            }

        case "RequestClosed":
            requests.removeAll { $0.id == requestId }

        case "MessagesDelivered":
            let ids = Set((e["message_ids"] as? [String]) ?? [])
            if var list = sent[sid] {
                for i in list.indices where ids.contains(list[i].id) { list[i].delivered = true }
                sent[sid] = list
            }
            say("📨 Message delivered to \(project)", for: 3)

        case "UserPromptSubmit":
            let task = AgentTask(id: sid, project: project, prompt: oneLine((e["prompt"] as? String) ?? ""),
                                 state: .working, started: Date())
            if let i = idx { tasks[i] = task } else { tasks.append(task) }
            say("On it! \(project) started 🛠️", for: 3)

        case "PostToolUse":
            // A tool ran: the agent is (back to) working. Also picks up sessions
            // that started before Agent Buddy was launched.
            if let i = idx {
                if tasks[i].state != .working { tasks[i].state = .working; tasks[i].finished = nil }
            } else {
                tasks.append(AgentTask(id: sid, project: project, prompt: "(already running)", state: .working, started: Date()))
            }

        case "Notification":
            let type = (e["notification_type"] as? String) ?? ""
            let msg = (e["message"] as? String) ?? "needs your attention"
            // "Waiting for your input" fires after a task is already done; Stop covers it.
            if type == "idle_prompt" || msg.localizedCaseInsensitiveContains("waiting for your input") { return }
            if let i = idx { tasks[i].state = .waiting }
            else { tasks.append(AgentTask(id: sid, project: project, prompt: "", state: .waiting, started: Date())) }
            say("🙋 \(project): \(msg)", for: 10, action: .session(sid))
            notify(title: "🙋 \(project) needs you", body: msg, sound: "Ping")

        case "Stop":
            let started = idx.map { tasks[$0].started } ?? Date()
            let prompt = idx.map { tasks[$0].prompt } ?? ""
            if let i = idx { tasks[i].state = .done; tasks[i].finished = Date() }
            else { tasks.append(AgentTask(id: sid, project: project, prompt: "", state: .done, started: Date(), finished: Date())) }
            let dur = formatDuration(Date().timeIntervalSince(started))
            celebrateUntil = Date().addingTimeInterval(4)
            let summary = doneSummary((e["last_message"] as? String) ?? "")
            if let i = tasks.firstIndex(where: { $0.id == sid }) { tasks[i].summary = summary.isEmpty ? nil : summary }
            logToday { $0.agentsDone.append(.init(project: project, text: summary.isEmpty ? (prompt.isEmpty ? "done" : prompt) : summary, at: Date())) }
            say(summary.isEmpty ? "✅ \(project) is done! (\(dur))" : "✅ \(project): \(summary)", for: 10, action: .session(sid))
            if let ids = herdrPending.removeValue(forKey: sid), let t = tasks.first(where: { $0.id == sid }) {
                deliverHerdr(ids, to: t)
            }
            notify(title: "✅ \(project) finished",
                   body: prompt.isEmpty ? "Agent task completed in \(dur)" : "\(prompt) — \(dur)",
                   sound: "Glass")
            if let rid = requestId {
                requests.append(PendingRequest(id: rid, sessionId: sid, project: project,
                                               kind: .reply(lastMessage: (e["last_message"] as? String) ?? "")))
            }

        case "SubagentStop":
            if let i = idx { tasks[i].subagents += 1 }
            say("🤖 A sub-agent in \(project) finished", for: 3)

        case "SessionEnd":
            tasks.removeAll { $0.id == sid }
            sent[sid] = nil
            try? FileManager.default.removeItem(at: inboxDir.appendingPathComponent("\(sid).jsonl"))

        default:
            break
        }

        if let i = tasks.firstIndex(where: { $0.id == sid }) {
            if isCodex && tasks[i].kind != "codex" { tasks[i].kind = "codex" }
            if let cwd = e["cwd"] as? String, !cwd.isEmpty, tasks[i].cwd != cwd { tasks[i].cwd = cwd }
            tasks[i].lastActivity = Date()
            if let path = e["transcript_path"] as? String, tasks[i].transcript != path { tasks[i].transcript = path }
            if let target = TerminalTarget(event: e), tasks[i].terminal != target {
                tasks[i].terminal = target
                // Hooks now track this pane; drop the herdr-only placeholder for it.
                if let pane = target.herdrPane { tasks.removeAll { $0.id == "herdr:" + pane } }
            }
        }
    }

    // MARK: Chat

    func openChat(_ sessionId: String) {
        withAnimation(.spring) { chatSession = sessionId; expanded = true }
        chatHistory = []
        refreshChat()
    }

    func closeChat() { chatSession = nil; chatHistory = []; screenText = "" }

    /// Clicking the robot: open the panel, or close it (and any chat) leaving just the robot.
    private var lastToggle = Date.distantPast

    func togglePanel() {
        // One click = one toggle, even if the click is delivered twice.
        guard Date().timeIntervalSince(lastToggle) > 0.35 else { return }
        lastToggle = Date()
        if napping { wake(); withAnimation(.spring) { expanded = true }; return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            if expanded { closeChat(); expanded = false } else { expanded = true }
        }
    }

    func closePanel() { if expanded { togglePanel() } }

    private func refreshChat() {
        lastChatLoad = Date()
        if let sid = chatSession, let task = tasks.first(where: { $0.id == sid }), task.usesScreen,
           let pane = task.terminal?.herdrPane {
            herdrQueue.async {
                let text = Herdr.screen(pane)
                DispatchQueue.main.async { if self.chatSession == sid { self.screenText = text } }
            }
            return
        }
        guard let sid = chatSession, let path = tasks.first(where: { $0.id == sid })?.transcript else { return }
        chatQueue.async {
            let items = loadTranscript(path)
            DispatchQueue.main.async { if self.chatSession == sid { self.chatHistory = items } }
        }
    }

    /// Transcript messages plus the ones posted from the bot, in time order.
    func chatItems(for sessionId: String) -> [ChatItem] {
        let history = chatSession == sessionId ? chatHistory : []
        // Messages typed into the terminal show up in the transcript; don't show them twice.
        let seen = Set(history.filter(\.fromUser).map(\.text))
        let mine = (sent[sessionId] ?? []).filter { !seen.contains($0.text) }.map {
            ChatItem(id: $0.id, fromUser: true, text: $0.text, date: $0.date,
                     status: $0.delivered ? "delivered"
                        : $0.via == "terminal" ? "sending"
                        : $0.via == "waiting" ? "sends when idle"
                        : $0.via == "failed" ? "failed" : "queued")
        }
        return (history + mine).sorted { $0.date < $1.date }
    }

    /// Posts a message to an agent:
    /// - waiting at Stop in remote mode → continues it right away;
    /// - idle in a herdr pane / Terminal tab → submitted there as a new prompt;
    /// - otherwise → queued for the hook to deliver at the agent's next step.
    func sendChat(_ text: String, to sessionId: String) {
        var msg = SentMessage(id: UUID().uuidString, text: text, date: Date(), delivered: false)
        let task = tasks.first { $0.id == sessionId }
        if let req = requests.first(where: { $0.sessionId == sessionId && $0.isReply }) {
            answer(req, ["action": "reply", "text": text])
            msg.delivered = true
        } else if let task, task.usesScreen {
            // No hooks: only an idle agent can take a prompt, so hold it until then.
            if task.state == .done {
                msg.via = "terminal"
                sent[sessionId, default: []].append(msg)
                deliverHerdr([msg.id], to: task)
                return
            }
            msg.via = "waiting"
            herdrPending[sessionId, default: []].append(msg.id)
        } else if let task, task.state == .done, let target = task.terminal {
            msg.via = "terminal"
            let project = task.project
            chatQueue.async {
                let error = target.submit(text)
                DispatchQueue.main.async {
                    if let error {
                        // Couldn't type it in; fall back to the queue.
                        self.enqueue(text, id: msg.id, for: sessionId)
                        self.updateSent(sessionId, msg.id) { $0.via = nil }
                        self.say("⚠️ Couldn't reach \(project)'s terminal (\(error)). Message queued.", for: 6)
                    } else {
                        self.updateSent(sessionId, msg.id) { $0.delivered = true }
                        self.say("📨 Sent to \(project)", for: 3)
                    }
                }
            }
        } else {
            enqueue(text, id: msg.id, for: sessionId)
        }
        sent[sessionId, default: []].append(msg)
    }

    /// Submits held messages to an idle herdr-only agent as one prompt.
    private func deliverHerdr(_ ids: [String], to task: AgentTask) {
        guard let pane = task.terminal?.herdrPane else { return }
        let texts = (sent[task.id] ?? []).filter { ids.contains($0.id) }.map(\.text)
        guard !texts.isEmpty else { return }
        for id in ids { updateSent(task.id, id) { $0.via = "terminal" } }
        let project = task.project
        herdrQueue.async {
            let error = Herdr.prompt(pane, texts.joined(separator: "\n\n"))
            DispatchQueue.main.async {
                for id in ids {
                    self.updateSent(task.id, id) {
                        if error == nil { $0.delivered = true } else { $0.via = "failed" }
                    }
                }
                if let error { self.say("⚠️ Couldn't send to \(project) (\(error))", for: 6) }
                else { self.say("📨 Sent to \(project)", for: 3) }
            }
        }
    }

    func jump(to task: AgentTask) {
        guard let target = task.terminal else { return }
        chatQueue.async { target.focus() }
    }

    // MARK: herdr

    private func pollHerdr() {
        guard Herdr.bin != nil else { return }
        herdrPolling = true
        lastHerdrPoll = Date()
        herdrQueue.async {
            let agents = Herdr.list()
            DispatchQueue.main.async {
                self.herdrPolling = false
                if let agents { self.mergeHerdr(agents) }
            }
        }
    }

    private func mergeHerdr(_ agents: [HerdrAgent]) {
        let now = Date()
        let byPane = Dictionary(agents.map { ($0.pane, $0) }, uniquingKeysWith: { a, _ in a })
        let hookPanes = Set(tasks.filter { !$0.isHerdrOnly }.compactMap { $0.terminal?.herdrPane })

        // Hook-tracked Claude sessions: herdr knows if one was interrupted (no Stop
        // hook fires on Esc) or its pane was closed.
        for i in tasks.indices.reversed() where !tasks[i].isHerdrOnly {
            guard let pane = tasks[i].terminal?.herdrPane else { continue }
            guard let a = byPane[pane] else { tasks.remove(at: i); continue }
            if tasks[i].state == .working && (a.status == "idle" || a.status == "done")
                && now.timeIntervalSince(tasks[i].lastActivity) > 15 {
                tasks[i].state = .done
                tasks[i].finished = now
            }
        }

        for a in agents {
            if hookPanes.contains(a.pane) { continue } // hooks already track this agent (Claude or Codex)
            let id = "herdr:" + a.pane
            let state: TaskState = a.status == "working" ? .working : a.status == "blocked" ? .waiting : .done
            var target = TerminalTarget()
            target.herdrPane = a.pane
            let name = a.kind == "claude" ? a.project : "\(a.kind) · \(a.project)"

            guard let i = tasks.firstIndex(where: { $0.id == id }) else {
                var t = AgentTask(id: id, project: name, prompt: a.title, state: state, started: now,
                                  finished: state == .done ? now : nil, terminal: target, kind: a.kind)
                t.cwd = a.cwd
                tasks.append(t)
                if herdrSeeded && state == .working { say("On it! \(name) started 🛠️", for: 3) }
                continue
            }
            let old = tasks[i].state
            if tasks[i].prompt != a.title { tasks[i].prompt = a.title }
            guard old != state else { continue }
            tasks[i].state = state
            tasks[i].lastActivity = now
            switch state {
            case .working:
                tasks[i].started = now
                tasks[i].finished = nil
            case .waiting:
                say("🙋 \(name) needs you", for: 10)
                notify(title: "🙋 \(name) needs you", body: a.title, sound: "Ping")
            case .done:
                tasks[i].finished = now
                if old == .working {
                    let dur = formatDuration(now.timeIntervalSince(tasks[i].started))
                    celebrateUntil = now.addingTimeInterval(4)
                    say("✅ \(name) is done! (\(dur))", for: 8)
                    notify(title: "✅ \(name) finished", body: a.title.isEmpty ? "Done in \(dur)" : "\(a.title) — \(dur)", sound: "Glass")
                }
                if let ids = herdrPending.removeValue(forKey: id) { deliverHerdr(ids, to: tasks[i]) }
            }
        }

        // Panes that closed.
        tasks.removeAll { $0.isHerdrOnly && byPane[String($0.id.dropFirst("herdr:".count))] == nil }
        herdrSeeded = true
    }

    // MARK: Cloud

    private func pollCloudIfDue(_ now: Date) {
        // ECS: every 3 min, every 30 s while something is deploying or short on tasks.
        let busy = ecs.contains { $0.deploying || $0.running < $0.desired } || deploys.contains { $0.isActive }
            || cloudRun.contains { $0.deploying || $0.isUnhealthy }
        let cloudDue = now.timeIntervalSince(lastEcsPoll) > (busy ? 30 : 180)
        let ecsDue = !(config.ecsClusters ?? []).isEmpty && !aws.isLoggedOut && cloudDue
        let runDue = !gcpProjects.isEmpty && Gcp.bin != nil && !gcp.isLoggedOut && cloudDue
        let codexDue = CodexCloud.bin != nil && now.timeIntervalSince(lastCodexPoll) > (codexSignedIn ? 60 : 600)
        guard ecsDue || codexDue || runDue else { return }
        cloudPolling = true
        if ecsDue || runDue { lastEcsPoll = now }
        let projects = gcpProjects
        if codexDue { lastCodexPoll = now }
        let clusters = config.ecsClusters ?? []
        let region = ecsRegion
        stackQueue.async {
            let ecsResult = ecsDue ? EcsMonitor.poll(clusters: clusters, region: region) : nil
            let codexResult = codexDue ? CodexCloud.poll() : nil
            let runResult = runDue ? Gcp.cloudRun(projects) : nil
            DispatchQueue.main.async {
                self.cloudPolling = false
                if let ecsResult { self.mergeEcs(ecsResult) }
                if let runResult { self.mergeCloudRun(runResult) }
                if let codexResult { self.mergeCodex(codexResult) }
            }
        }
    }

    private func mergeEcs(_ result: EcsMonitor.Result) {
        guard case let .ok(services, problems) = result else {
            if case .loggedOut = result { checkAws() }
            return
        }
        let now = Date()
        for s in services {
            let label = "\(s.cluster) · \(s.short)" + (s.isProduction ? " (production)" : "")
            if s.rollout == "FAILED", ecsSeeded, !ecsAlerted.contains(s.id + "failed") {
                ecsAlerted.insert(s.id + "failed")
                alertUntil = now.addingTimeInterval(6)
                sayWork("❌ ECS rollout failed: \(label)\n\(s.lastEvent)", for: 14)
                notify(title: "❌ ECS rollout failed: \(label)", body: s.lastEvent, sound: "Basso")
            }
            if s.running < s.desired && !s.deploying {
                let since = ecsShortSince[s.id] ?? now
                ecsShortSince[s.id] = since
                if now.timeIntervalSince(since) >= 180, !ecsAlerted.contains(s.id) {
                    ecsAlerted.insert(s.id)
                    alertUntil = now.addingTimeInterval(6)
                    sayWork("⚠️ \(label): \(s.running) of \(s.desired) tasks running\n\(s.stopReason ?? s.lastEvent)", for: 14)
                    notify(title: "⚠️ \(label): \(s.running)/\(s.desired) tasks running", body: s.stopReason ?? s.lastEvent, sound: "Basso")
                }
            } else {
                ecsShortSince[s.id] = nil
                if ecsAlerted.remove(s.id) != nil { sayWork("✅ \(label) is healthy again (\(s.running)/\(s.desired))", for: 5) }
                if s.rollout != "FAILED" { ecsAlerted.remove(s.id + "failed") }
            }
        }
        ecsSeeded = true
        if ecs != services { ecs = services }
        if ecsProblems != problems { ecsProblems = problems }
    }

    private func mergeCodex(_ result: CodexCloud.Result) {
        switch result {
        case .notSignedIn:
            codexSignedIn = false
            if !codexCloud.isEmpty { codexCloud = [] }
        case .unavailable:
            break
        case .ok(let new):
            codexSignedIn = true
            if codexSeeded {
                for t in new {
                    guard let old = codexCloud.first(where: { $0.id == t.id }), old.state != t.state else { continue }
                    if t.state == .done {
                        celebrateUntil = Date().addingTimeInterval(4)
                        say("✅ Codex cloud task done: \(t.title)", for: 8)
                        notify(title: "✅ Codex cloud task done", body: t.title, sound: "Glass")
                    } else if t.state == .failed {
                        alertUntil = Date().addingTimeInterval(5)
                        say("❌ Codex cloud task failed: \(t.title)", for: 10)
                        notify(title: "❌ Codex cloud task failed", body: t.title, sound: "Basso")
                    }
                }
            }
            codexSeeded = true
            if codexCloud != new { codexCloud = new }
        }
    }

    func codexLogin() {
        stackQueue.async { CodexCloud.openLogin() }
        lastCodexPoll = Date().addingTimeInterval(-50) // re-check soon
        say("Sign in to ChatGPT in your browser; I'll pick up your Codex cloud tasks after.", for: 6)
    }

    // MARK: Google Cloud

    func checkGcp() {
        gcpChecking = true
        lastGcpCheck = Date()
        stackQueue.async {
            let status = Gcp.loginStatus()
            DispatchQueue.main.async {
                self.gcpChecking = false
                let was = self.gcp
                if status != was { self.gcp = status }
                guard !self.gcpProjects.isEmpty else { return } // only nag if you watch GCP projects
                if case .loggedOut = status, !was.isLoggedOut {
                    self.sayWork("🔑 Google Cloud login expired. Click me, then Log in.", for: 12, action: .tab(.cloud))
                } else if case .active(let who) = status, was.isLoggedOut {
                    self.gcpFastUntil = .distantPast
                    self.sayWork("✅ Google Cloud login active (\(who))", for: 4)
                }
            }
        }
    }

    func loginGcp() {
        stackQueue.async { Gcp.openLogin() }
        gcpFastUntil = Date().addingTimeInterval(240)
        say("🔑 Finish signing in to Google in your browser. I'll notice when you're done.", for: 6)
    }

    private func mergeCloudRun(_ result: Gcp.Result) {
        guard case let .ok(services, problems) = result else {
            if case .loggedOut = result { checkGcp() }
            return
        }
        if cloudRunSeeded {
            for s in services {
                let label = "Cloud Run \(s.name)" + (s.isProduction ? " (production)" : "")
                let was = cloudRun.first { $0.id == s.id }
                if s.isUnhealthy && was?.isUnhealthy != true {
                    alertUntil = Date().addingTimeInterval(6)
                    sayWork("⚠️ \(label) isn't ready\n\(s.message)", for: 14, action: .tab(.cloud))
                } else if !s.isUnhealthy && was?.isUnhealthy == true {
                    sayWork("✅ \(label) is healthy again", for: 5)
                }
            }
        }
        cloudRunSeeded = true
        if cloudRun != services { cloudRun = services }
        if gcpProblems != problems { gcpProblems = problems }
    }

    // MARK: AWS login

    func checkAws() {
        awsChecking = true
        lastAwsCheck = Date()
        stackQueue.async {
            let status = AwsLogin.check()
            DispatchQueue.main.async {
                self.awsChecking = false
                let was = self.aws
                if status != was { self.aws = status }
                if case .loggedOut = status, !was.isLoggedOut {
                    self.alertUntil = Date().addingTimeInterval(5)
                    self.sayWork("🔑 AWS CLI login expired. Click me, then Log in.", for: 12)
                    self.notify(title: "🔑 AWS login expired", body: "Run aws login before your agents need AWS.", sound: "Funk")
                } else if case .active(let who) = status, was.isLoggedOut {
                    self.awsFastUntil = .distantPast
                    self.sayWork("✅ AWS login active (\(who))", for: 4)
                }
            }
        }
    }

    func loginAws() {
        stackQueue.async { AwsLogin.openLogin() }
        awsFastUntil = Date().addingTimeInterval(240)
        say("🔑 Finish signing in in your browser. I'll notice when you're done.", for: 6)
    }

    // MARK: Local dev stacks

    private func pollStacks() {
        stackPolling = true
        lastStackPoll = Date()
        stackQueue.async {
            let (stacks, tunnels) = self.stackMonitor.poll()
            // Follow the logs of services that are up (down ones already alert on their own).
            let logs = stacks.flatMap { st in
                st.services.filter { $0.status == .up && !$0.logPath.isEmpty }.map { (st.name, $0.name, $0.logPath) }
            }
            let errors = self.logWatcher.scan(logs.map { (stack: $0.0, service: $0.1, path: $0.2) })
            DispatchQueue.main.async {
                self.stackPolling = false
                self.mergeStacks(stacks, tunnels)
                for err in errors {
                    self.logErrors.insert(err, at: 0)
                    self.sayWork("🐞 \(err.stack) · \(err.service): \(err.line)", for: 12, action: .tab(.code))
                }
                if self.logErrors.count > 12 { self.logErrors.removeLast(self.logErrors.count - 12) }
            }
        }
    }

    private func mergeStacks(_ new: [DevStack], _ newTunnels: [Tunnel]) {
        if stackSeeded {
            for stack in new {
                guard let old = stacks.first(where: { $0.path == stack.path }) else { continue }
                for svc in stack.services where svc.status == .down || svc.status == .notListening {
                    guard let before = old.services.first(where: { $0.name == svc.name }),
                          before.status == .up || before.status == .starting else { continue }
                    let what = svc.status == .down ? "stopped" : "isn't answering on port \(svc.port ?? 0)"
                    alertUntil = Date().addingTimeInterval(6)
                    sayWork("💥 \(stack.name): \(svc.name) \(what)" + (svc.error.map { "\n\($0)" } ?? ""), for: 14)
                    notify(title: "💥 \(stack.name): \(svc.name) \(what)", body: svc.error ?? "Open the panel for details.", sound: "Basso")
                }
                for svc in stack.services where svc.status == .up {
                    if let before = old.services.first(where: { $0.name == svc.name }),
                       before.status == .down || before.status == .notListening {
                        sayWork("✅ \(stack.name): \(svc.name) is back up", for: 4)
                    }
                }
            }
            for t in newTunnels where t.isProduction && !tunnels.contains(t) {
                sayWork("⚠️ A tunnel to \(t.env) (production) database is open on port \(t.port)", for: 10)
                notify(title: "⚠️ Production tunnel open: \(t.env)", body: "Port \(t.port). Be careful with writes.", sound: "Funk")
            }
        }
        stackSeeded = true
        if stacks != new { stacks = new }
        if tunnels != newTunnels { tunnels = newTunnels }
    }

    func openLog(_ svc: StackService) {
        guard !svc.logPath.isEmpty, FileManager.default.fileExists(atPath: svc.logPath) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: svc.logPath))
    }

    func restartStack(_ stack: DevStack) {
        stackQueue.async { StackMonitor.restart(stack) }
        say("🔄 Running make debug in \(stack.name)…", for: 4)
    }

    /// Hands the crash to an agent working in the same repo: idle ones first.
    func askAgentToFix(_ stack: DevStack, _ svc: StackService) {
        let candidates = tasks.filter { $0.project == stack.name || $0.project.hasSuffix("· \(stack.name)") }
        guard let agent = candidates.first(where: { $0.state == .done }) ?? candidates.first else {
            say("No agent is open in \(stack.name). Start one there and try again.", for: 6)
            return
        }
        let log = svc.logPath.isEmpty ? "" : StackMonitor.tail(of: svc.logPath)
        let text = "My local `\(svc.name)` service in \(stack.path) (env: \(stack.env)) "
            + (svc.status == .down ? "stopped." : svc.status == .up ? "is logging errors." : "isn't answering on port \(svc.port ?? 0).")
            + (log.isEmpty ? "" : " Last lines of .dev-logs/\(svc.name).log:\n```\n\(log)\n```\n")
            + "Find the cause and fix it in the code. Don't touch any deployed or production environment."
        sendChat(text, to: agent.id)
        say("🛠️ Sent the \(svc.name) crash to \(agent.project)", for: 5)
    }

    // MARK: Stuck agents

    private func checkStuck(_ now: Date) {
        lastStuckCheck = now
        let waitLimit = (config.stuckWaitingMinutes ?? 10) * 60
        let quietLimit = (config.stuckQuietMinutes ?? 20) * 60
        for i in tasks.indices {
            let t = tasks[i]
            let waiting = t.state == .waiting || requests.contains { $0.sessionId == t.id }
            if waiting && t.waitingSince == nil { tasks[i].waitingSince = now }
            if !waiting && t.waitingSince != nil { tasks[i].waitingSince = nil }

            var alert: (key: String, text: String)?
            if waiting, let since = tasks[i].waitingSince {
                let waited = now.timeIntervalSince(since)
                if waited >= waitLimit * 3 { alert = ("wait2", "⏰ \(t.project) has been waiting for you for \(formatDuration(waited))") }
                else if waited >= waitLimit { alert = ("wait1", "⏰ \(t.project) has been waiting for you for \(formatDuration(waited))") }
            } else if t.state == .working && !t.isHerdrOnly && now.timeIntervalSince(t.lastActivity) >= quietLimit {
                alert = ("quiet", "🐢 \(t.project) has shown no activity for \(formatDuration(now.timeIntervalSince(t.lastActivity))). It may be stuck, or running a long command.")
            }

            guard let alert else { nagged[t.id] = nil; continue }
            if nagged[t.id] == alert.key || (nagged[t.id] == "wait2" && alert.key == "wait1") { continue }
            nagged[t.id] = alert.key
            alertUntil = now.addingTimeInterval(5)
            sayWork(alert.text, for: 12)
            notify(title: alert.key == "quiet" ? "🐢 \(t.project) may be stuck" : "⏰ \(t.project) is waiting for you",
                   body: alert.text, sound: "Submarine")
        }
    }

    // MARK: Break reminders

    private func checkBreak(_ now: Date) {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                          eventType: CGEventType(rawValue: ~0) ?? .mouseMoved)
        quietNow = napping || microphoneInUse()
        lastIdle = idle
        checkAutoRemote(idle: idle)
        checkJuggling(now)
        trackToday(now, idle: idle)
        checkWater(now, idle: idle)
        checkDaily(now, idle: idle)
        checkWorkday(now, idle: idle)
        if var hold = activityHold {
            if idle >= 300 { hold.sawAway = true }
            activityHold = (hold.sawAway && idle < 30) || now > hold.until ? nil : hold
            if activityHold == nil { say("Welcome back! 👋", for: 4) }
        }
        updateActivity(now)
        if idle >= (config.breakResetMinutes ?? 5) * 60 {
            // Away from the computer long enough: that was a break.
            workStreakStart = nil
            if breakDue { withAnimation(.spring) { breakDue = false } }
            return
        }
        if workStreakStart == nil { workStreakStart = now }
        guard let start = workStreakStart, now > breaksSnoozedUntil, !quietNow, !offDuty else { return }
        let worked = now.timeIntervalSince(start)
        if worked >= (config.breakMinutes ?? 90) * 60 && now.timeIntervalSince(lastBreakNag) >= 20 * 60 {
            lastBreakNag = now
            withAnimation(.spring) { breakDue = true }
            say("🧘 Time for a break! Click me for options.", for: 10)
            notify(title: "🧘 Time for a break",
                   body: "You've been working for \(formatDuration(worked)). Stand up, stretch, drink some water.", sound: "Purr")
        }
    }

    /// Every hour, but only while you're at the computer: if you're away when it's
    /// due, it waits and reminds you when you're back.
    private func checkWater(_ now: Date, idle: TimeInterval) {
        guard waterOn, !waterDue, !quietNow, !offDuty, now >= nextWater, idle < 120 else { return }
        withAnimation(.spring) { waterDue = true }
        updateActivity(now)
        say("💧 Time for some water! Take a glass.", for: 15)
        notify(title: "💧 Drink some water", body: "Another hour has gone by. Take a glass of water.", sound: "Glass")
    }

    /// Fires each daily reminder once a day at its time. If the Mac was asleep or
    /// you were away, it fires when you're back (within 2 hours of the time).
    private func checkDaily(_ now: Date, idle: TimeInterval) {
        guard dueReminder == nil, !quietNow, idle < 120 else { return }
        let cal = Calendar.current
        let day = DateFormatter.localizedString(from: now, dateStyle: .short, timeStyle: .none)
        for r in config.dailyReminders ?? [DailyReminder.lunch] {
            let parts = r.time.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2,
                  let at = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now) else { continue }
            let key = "reminderFired.\(r.time).\(r.title)"
            let snoozed = reminderSnoozedUntil[key]
            let dueBySchedule = now >= at && now < at.addingTimeInterval(2 * 3600)
                && UserDefaults.standard.string(forKey: key) != day
            let dueBySnooze = snoozed.map { now >= $0 } ?? false
            guard dueBySchedule || dueBySnooze else { continue }
            UserDefaults.standard.set(day, forKey: key)
            reminderSnoozedUntil[key] = nil
            let icon = r.emoji ?? "⏰"
            withAnimation(.spring) { dueReminder = r }
            updateActivity(now)
            say("\(icon) \(r.title)! \(r.message)", for: 20)
            notify(title: "\(icon) \(r.title)", body: r.message, sound: "Hero")
            return
        }
    }

    func dismissReminder(tookBreak: Bool) {
        if tookBreak {
            workStreakStart = Date(); lastBreakNag = .distantPast; breakDue = false
            if let a = dueReminder?.activity.flatMap(BuddyActivity.init(rawValue:)) {
                activityHold = (a, Date().addingTimeInterval(a == .sleep ? 10 * 3600 : 90 * 60), false)
            }
        }
        let wasSleep = dueReminder?.activity == "sleep"
        withAnimation(.spring) { dueReminder = nil; expanded = false }
        say(tookBreak ? (wasSleep ? "Good night! 🌙" : "Enjoy! 😋") : "Okay.", for: 3)
        updateActivity(Date())
    }

    /// Reminder due → act it out; then any hold from "Going for lunch/sleep".
    private func updateActivity(_ now: Date) {
        let a = (napping || now < yawnUntil || (offDuty && lastIdle > 300) ? .sleep : nil)
            ?? dueReminder?.activity.flatMap(BuddyActivity.init(rawValue:))
            ?? (waterDue || now < drinkUntil ? .drink : nil)
            ?? activityHold?.activity
        if a != activity { withAnimation(.spring) { activity = a } }
    }

    func snoozeReminder(minutes: Double) {
        guard let r = dueReminder else { return }
        reminderSnoozedUntil["reminderFired.\(r.time).\(r.title)"] = Date().addingTimeInterval(minutes * 60)
        withAnimation(.spring) { dueReminder = nil }
        say("Okay, I'll remind you in \(Int(minutes)) min.", for: 3)
    }

    func drankWater() {
        nextWater = Date().addingTimeInterval(waterInterval)
        drinkUntil = Date().addingTimeInterval(5) // a few happy sips
        withAnimation(.spring) { waterDue = false }
        say("Nice! 💧 Next reminder in \(Int(waterInterval / 60)) min.", for: 3)
    }

    func snoozeWater(minutes: Double) {
        nextWater = Date().addingTimeInterval(minutes * 60)
        withAnimation(.spring) { waterDue = false }
        say("Okay, I'll remind you in \(Int(minutes)) min.", for: 3)
    }

    var workedFor: TimeInterval { workStreakStart.map { Date().timeIntervalSince($0) } ?? 0 }

    func tookBreak() {
        workStreakStart = Date()
        lastBreakNag = .distantPast
        withAnimation(.spring) { breakDue = false }
        say("Nice! Timer reset 💪", for: 3)
    }

    func snoozeBreaks(minutes: Double) {
        breaksSnoozedUntil = Date().addingTimeInterval(minutes * 60)
        lastBreakNag = .distantPast
        withAnimation(.spring) { breakDue = false }
        say("Okay, I'll remind you in \(Int(minutes)) min", for: 3)
    }

    private func updateSent(_ sessionId: String, _ id: String, _ change: (inout SentMessage) -> Void) {
        guard var list = sent[sessionId], let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        sent[sessionId] = list
    }

    private func enqueue(_ text: String, id: String, for sessionId: String) {
        let line: [String: Any] = ["id": id, "text": text, "ts": Date().timeIntervalSince1970]
        guard var data = try? JSONSerialization.data(withJSONObject: line) else { return }
        data.append(0x0A)
        let path = inboxDir.appendingPathComponent("\(sessionId).jsonl").path
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        if fd >= 0 {
            data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
            close(fd)
        }
    }

    /// Sends the user's answer to the waiting hook.
    func answer(_ request: PendingRequest, _ reply: [String: Any]) {
        let url = repliesDir.appendingPathComponent("\(request.id).json")
        if let data = try? JSONSerialization.data(withJSONObject: reply) { try? data.write(to: url, options: .atomic) }
        withAnimation(.spring) { requests.removeAll { $0.id == request.id } }
        if let i = tasks.firstIndex(where: { $0.id == request.sessionId }) {
            let action = reply["action"] as? String
            if action == "allow" || action == "deny" || action == "reply" {
                tasks[i].state = .working
                tasks[i].finished = nil
                if action == "reply" { tasks[i].started = Date(); tasks[i].prompt = oneLine(reply["text"] as? String ?? "") }
            }
        }
    }

    // MARK: Deploys

    private func mergeDeploys(repo: String, runs: [DeployRun]) {
        // The first poll of a repo only fills the list; it doesn't announce old runs.
        let firstPoll = seededRepos.insert(repo).inserted
        let now = Date()
        for run in runs {
            if let i = deploys.firstIndex(where: { $0.id == run.id }) {
                let wasActive = deploys[i].isActive
                deploys[i] = run
                if wasActive && !run.isActive { deployFinished(run) }
            } else if now.timeIntervalSince(run.created) < 6 * 3600 {
                deploys.append(run)
                guard !firstPoll else { continue }
                if run.isActive {
                    sayWork("🚀 \(run.repoName): \(run.workflow) started (\(run.branch))", for: 4)
                } else {
                    deployFinished(run)
                }
            }
        }
        deploys.removeAll { !$0.isActive && now.timeIntervalSince($0.updated) > 6 * 3600 }
        deploys.sort { $0.created > $1.created }
        if deploys.count > 15 { deploys.removeLast(deploys.count - 15) }
    }

    private func deployFinished(_ run: DeployRun) {
        let what = "\(run.workflow) (\(run.branch))"
        logToday { $0.deploys.append(.init(project: run.repoName, text: "\(what) · \(run.conclusion)", at: Date())) }
        sitesFastUntil = Date().addingTimeInterval(600) // watch the sites closely for 10 min
        lastSitesPoll = .distantPast
        switch run.conclusion {
        case "success":
            celebrateUntil = Date().addingTimeInterval(4)
            sayWork("🚀 \(run.repoName) deployed! \(what)", for: 8)
            notify(title: "🚀 \(run.repoName) deployed", body: what, sound: "Hero")
        case "cancelled", "skipped":
            sayWork("⏹️ \(run.repoName): \(what) \(run.conclusion)", for: 5)
        default:
            alertUntil = Date().addingTimeInterval(6)
            sayWork("❌ \(run.repoName) deploy \(run.conclusion): \(what)", for: 12)
            notify(title: "❌ \(run.repoName) deploy \(run.conclusion)", body: what, sound: "Basso")
        }
    }

    /// Work alerts (PRs, deploys, ECS, sites, local errors, …): quiet outside your work hours.
    private func sayWork(_ text: String, for seconds: TimeInterval, action: BubbleAction? = nil) {
        guard !offDuty else { return }
        say(text, for: seconds, action: action)
    }

    private func say(_ text: String, for seconds: TimeInterval, action: BubbleAction? = nil) {
        // Napping: keep it for the "while you napped" summary instead.
        if napping {
            napLog.append(text)
            if napLog.count > 30 { napLog.removeFirst() }
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { bubble = text; bubbleAction = action }
        bubbleUntil = Date().addingTimeInterval(seconds)
    }

    /// Click on the bubble: jump to that agent (or open the link); otherwise open the panel.
    func bubbleTapped() {
        switch bubbleAction {
        case .session(let sid)?:
            if let task = tasks.first(where: { $0.id == sid }) {
                if task.terminal != nil { jump(to: task) } else { openChat(sid) }
            } else { togglePanel() }
        case .url(let url)?:
            NSWorkspace.shared.open(url)
        case .tab(let tab)?:
            panelTab = tab
            if !expanded { togglePanel() }
        case nil:
            togglePanel()
        }
        withAnimation(.easeOut(duration: 0.2)) { bubble = nil; bubbleAction = nil }
    }

    // MARK: Nap

    /// Hold every alert and let the buddy sleep. nil minutes = until you wake it.
    func nap(minutes: Double?) {
        napLog = []
        withAnimation(.spring) {
            napUntil = minutes.map { Date().addingTimeInterval($0 * 60) } ?? .distantFuture
            bubble = nil; expanded = false
        }
        updateActivity(Date())
    }

    func wake() {
        guard napUntil != nil else { return }
        napUntil = nil
        let missed = napLog
        napLog = []
        withAnimation(.spring) { if !missed.isEmpty { napSummary = Array(missed.suffix(10)) } }
        updateActivity(Date())
        say(missed.isEmpty ? "☀️ I'm up! Nothing happened while I napped." : "☀️ I'm up! \(missed.count) update\(missed.count == 1 ? "" : "s") while I napped. Click me.", for: 8)
    }

    // MARK: Sites

    private func pollSites() {
        sitesPolling = true
        lastSitesPoll = Date()
        let list = config.sites ?? SiteChecker.defaults
        stackQueue.async {
            let results = SiteChecker.check(list)
            DispatchQueue.main.async {
                self.sitesPolling = false
                self.mergeSites(results)
            }
        }
    }

    private func mergeSites(_ results: [SiteStatus]) {
        var merged: [SiteStatus] = []
        for var r in results {
            let old = sites.first { $0.name == r.name }
            r.failures = r.ok ? 0 : (old?.failures ?? 0) + 1
            let label = r.name + (r.prod ? " (production)" : "")
            if r.failures == 2 {  // two misses in a row, not a blip
                alertUntil = Date().addingTimeInterval(6)
                sayWork("🌐 \(label) is down (\(r.code == 0 ? "no response" : "HTTP \(r.code)"))", for: 14,
                        action: URL(string: r.url).map { .url($0) })
                sitesFastUntil = Date().addingTimeInterval(600)
            } else if r.ok, let old, old.failures >= 2 {
                sayWork("✅ \(label) is back up", for: 5)
            }
            merged.append(r)
        }
        if sites != merged { sites = merged }
    }

    // MARK: Today's log

    private func logToday(_ change: (inout DayLog) -> Void) {
        rollDay(Date())
        change(&today)
        today.save()
    }

    private func rollDay(_ now: Date) {
        let key = DayLog.key(now)
        if today.day != key { today.save(); today = DayLog(day: key) }
    }

    /// Every ~10 s: time at the keyboard, and time agents spent working per project.
    private func trackToday(_ now: Date, idle: TimeInterval) {
        rollDay(now)
        let dt = min(now.timeIntervalSince(lastActiveTick), 15)
        lastActiveTick = now
        if idle < 120 { today.activeSeconds += dt }
        for t in tasks where t.state == .working {
            let name = t.project.replacingOccurrences(of: "codex · ", with: "")
            today.agentSeconds[name, default: 0] += dt
        }
        if now.timeIntervalSince(lastDaySave) > 60 { lastDaySave = now; today.save() }
    }

    /// Hands a failing PR to the agent working on its branch.
    func sendPRFix(_ pr: PullRequest) {
        guard let id = pr.agentId, let agent = tasks.first(where: { $0.id == id }) else { return }
        let text = "PR #\(pr.number) in \(pr.repo) (branch \(pr.headRef)) has failing CI checks: \(pr.url)\n"
            + (pr.ciError.map { "First error: \($0)\n" } ?? "")
            + "Find the cause, fix it on this branch, and push."
        sendChat(text, to: id)
        say("🛠️ Sent PR #\(pr.number)'s failure to \(agent.project)", for: 5)
    }

    func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(today.summary(), forType: .string)
        say("📋 Today's summary copied. Paste it into standup or Jira.", for: 4)
    }

    func askAgentAbout(_ err: LogError) {
        guard let stack = stacks.first(where: { $0.name == err.stack }),
              let svc = stack.services.first(where: { $0.name == err.service }) else { return }
        askAgentToFix(stack, svc)
    }

    // MARK: Pull requests

    private func pollPRs() {
        guard PRWatcher.gh != nil else { return }
        prPolling = true
        lastPRPoll = Date()
        let repos = config.repos
        let old = prs
        let agents = tasks.compactMap { t in t.cwd.map { (id: t.id, cwd: $0, idle: t.state == .done) } }
        stackQueue.async {
            guard var mine = PRWatcher.mine(repos: repos) else {
                DispatchQueue.main.async { self.prPolling = false }
                return
            }
            // Failing PRs: the first CI error, and a local agent on the same branch (idle ones first).
            let branchOf = PRWatcher.branches(of: agents.map(\.cwd))
            for i in mine.indices where mine[i].checks == .failing {
                mine[i].ciError = PRWatcher.ciError(mine[i])
                let onBranch = agents.filter { branchOf[$0.cwd] == mine[i].headRef }
                mine[i].agentId = (onBranch.first { $0.idle } ?? onBranch.first)?.id
            }
            let reviews = PRWatcher.reviewRequests()
            // PRs that dropped off the open list: merged or closed?
            let gone = old.filter { o in !mine.contains { $0.id == o.id } }
            let merged = gone.filter { PRWatcher.wasMerged($0) }
            DispatchQueue.main.async {
                self.prPolling = false
                self.mergePRs(mine, reviews, merged: merged)
            }
        }
    }

    private func mergePRs(_ mine: [PullRequest], _ reviews: [PullRequest], merged: [PullRequest]) {
        if prSeeded {
            for pr in merged {
                logToday { $0.prsMerged.append(.init(project: pr.repoName, text: "#\(pr.number) \(pr.title)", at: Date())) }
                celebrateUntil = Date().addingTimeInterval(5)
                sayWork("🎉 Merged: \(pr.repoName) #\(pr.number) \(pr.title)", for: 10, action: URL(string: pr.url).map { .url($0) })
            }
            for pr in mine {
                let link = URL(string: pr.url).map { BubbleAction.url($0) }
                guard let was = prs.first(where: { $0.id == pr.id }) else { continue }
                if pr.checks == .failing && was.checks != .failing {
                    alertUntil = Date().addingTimeInterval(6)
                    sayWork("❌ Checks failed: \(pr.repoName) #\(pr.number) \(pr.title)" + (pr.ciError.map { "\n\($0)" } ?? ""),
                            for: 14, action: .tab(.code))
                } else if pr.readyToMerge && !was.readyToMerge {
                    celebrateUntil = Date().addingTimeInterval(4)
                    sayWork("✅ Ready to merge: \(pr.repoName) #\(pr.number) \(pr.title)", for: 12, action: link)
                } else if pr.review == "CHANGES_REQUESTED" && was.review != "CHANGES_REQUESTED" {
                    sayWork("✏️ Changes requested: \(pr.repoName) #\(pr.number)", for: 10, action: link)
                }
            }
            for pr in reviews where !reviewPRs.contains(where: { $0.id == pr.id }) {
                sayWork("👀 Review requested: \(pr.repoName) #\(pr.number) \(pr.title)", for: 12, action: URL(string: pr.url).map { .url($0) })
            }
        }
        prSeeded = true
        if prs != mine { prs = mine }
        if reviewPRs != reviews { reviewPRs = reviews }
    }

    // MARK: Housekeeping

    private func scanHousekeeping() {
        lastHousekeeping = Date()
        let roots = projectRoots
        stackQueue.async {
            let h = Housekeeping.scan(roots: roots)
            DispatchQueue.main.async {
                let day = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
                if h.lowDisk && UserDefaults.standard.string(forKey: "lowDiskWarned") != day {
                    UserDefaults.standard.set(day, forKey: "lowDiskWarned")
                    self.sayWork(String(format: "💾 Disk is getting full: %.0f GB free. Click me for what to clean up.", h.freeGB), for: 12)
                }
                if self.housekeeping != h { self.housekeeping = h }
            }
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: End of the workday

    private func checkWorkday(_ now: Date, idle: TimeInterval) {
        let cal = Calendar.current
        let day = DateFormatter.localizedString(from: now, dateStyle: .short, timeStyle: .none)
        // Morning: yesterday's note, the first time you're at the computer.
        if yesterdayNote == nil, idle < 60, cal.component(.hour, from: now) >= 5,
           UserDefaults.standard.string(forKey: "noteShownOn") != day,
           let note = Notes.latest(), !cal.isDate(note.date, inSameDayAs: now), now.timeIntervalSince(note.date) < 4 * 86_400 {
            UserDefaults.standard.set(day, forKey: "noteShownOn")
            withAnimation(.spring) { yesterdayNote = note.text }
            say("📝 Your note from last time: \(note.text)", for: 20)
        }
        // Evening: wrap up.
        let parts = (config.workdayEnd ?? "20:00").split(separator: ":").compactMap { Int($0) }
        guard !endOfDayDue, !quietNow, idle < 120, parts.count == 2,
              let end = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now),
              now >= end, now < end.addingTimeInterval(3 * 3600),
              UserDefaults.standard.string(forKey: "workdayEndShown") != day else { return }
        UserDefaults.standard.set(day, forKey: "workdayEndShown")
        yawnUntil = now.addingTimeInterval(8)
        withAnimation(.spring) { endOfDayDue = true }
        updateActivity(now)
        say("🌇 That's the workday! Wrap up, and leave a note for tomorrow?", for: 15)
    }

    func saveNote(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { Notes.save(t) }
        noteDraft.text = ""
        withAnimation(.spring) { endOfDayDue = false }
        say(t.isEmpty ? "See you tomorrow 🌙" : "Saved. I'll show it to you tomorrow morning 🌙", for: 5)
    }

    private func notify(title: String, body: String, sound: String) {
        guard macNotifications else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "on run argv",
                       "-e", "display notification (item 2 of argv) with title (item 1 of argv) sound name (item 3 of argv)",
                       "-e", "end run", title, body, sound]
        try? p.run()
    }
}

// MARK: - Window dragging

final class WindowMover {
    weak var window: NSWindow?
    private var startMouse: NSPoint?
    private var startOrigin = NSPoint.zero
    private var moved = false

    func drag() {
        guard let w = window else { return }
        let m = NSEvent.mouseLocation
        if startMouse == nil { startMouse = m; startOrigin = w.frame.origin; moved = false }
        let dx = m.x - startMouse!.x, dy = m.y - startMouse!.y
        if abs(dx) + abs(dy) > 3 { moved = true }
        if moved { w.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)) }
    }

    /// Returns true if this gesture was a drag (not a click).
    func end() -> Bool {
        defer { startMouse = nil }
        if moved, let w = window {
            UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: w.frame.maxX, y: w.frame.minY)), forKey: "anchor")
        }
        return moved
    }

    /// Resizes the window to the content, keeping the robot's corner (bottom-right) in place.
    /// Grows right away (so an opening panel has room to animate in), but
    /// shrinks only after a closing animation has had time to finish.
    func fit(_ size: CGSize) {
        guard let w = window, size.width > 0, size.height > 0, startMouse == nil else { return }
        let f = w.frame
        shrinkWork?.cancel()
        if size.width > f.width || size.height > f.height {
            setSize(NSSize(width: max(size.width, f.width), height: max(size.height, f.height)))
        }
        if size.width < w.frame.width || size.height < w.frame.height {
            let work = DispatchWorkItem { [weak self] in self?.setSize(size) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    private var shrinkWork: DispatchWorkItem?

    private func setSize(_ size: NSSize) {
        guard let w = window, startMouse == nil else { return }
        let f = w.frame
        let new = NSRect(x: f.maxX - size.width, y: f.minY, width: size.width, height: size.height)
        if new.integral != f.integral { w.setFrame(new, display: true) }
    }
}

// MARK: - Shapes

struct Arc: Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY + r.height))
        }
        return p
    }
}

// MARK: - Character

struct BuddyCharacter: View {
    let character: BuddyCharacterKind
    let mood: Mood
    var waterDue = false
    var reminderEmoji: String? = nil
    var activity: BuddyActivity? = nil
    var prod = false
    let count: Int
    let alert: Bool
    let remote: Bool
    @Environment(\.isMeasuring) private var isMeasuring

    private let shell = LinearGradient(colors: [.white, Color(red: 0.86, green: 0.88, blue: 0.96)],
                                       startPoint: .top, endPoint: .bottom)
    private let outline = Color(red: 0.55, green: 0.58, blue: 0.70)
    private let screen = Color(red: 0.11, green: 0.13, blue: 0.23)
    private let eyeColor = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        if isMeasuring {
            Color.clear.frame(width: 130, height: 150)
        } else {
            ZStack {
                Buddy3DView(character: character, mood: mood, activity: activity)
                    .id(character) // a new scene when the character changes
                    .frame(width: 130, height: 150)
                    .offset(y: 4)
                // 2D effects and badges on top of the 3D robot.
                TimelineView(.animation(minimumInterval: mood == .idle ? 1.0 / 10 : 1.0 / 24)) { ctx in
                    overlays(t: ctx.date.timeIntervalSinceReferenceDate)
                }
            }
            .frame(width: 130, height: 150)
        }
    }

    private func overlays(t: Double) -> some View {
        ZStack {
            extras(t: t)
            if prod {
                Text("PROD")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color(red: 0.9, green: 0.15, blue: 0.25).opacity(0.75 + 0.25 * sin(t * 4))))
                    .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1))
                    .offset(y: 58)
            }
            switch activity {
            case .eat?:
                Text("🍜").font(.system(size: 24)).offset(x: 0, y: 30)
                Text("nom").font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Mood.working.color)
                    .opacity(0.5 + 0.5 * sin(t * 9))
                    .offset(x: 34, y: -30)
            case .drink?:
                Text("🥤").font(.system(size: 20)).offset(x: 20, y: -16 + sin(t * 2) * 1.5)
            case .sleep?:
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Text("z").font(.system(size: 10 + CGFloat(i) * 4, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.62, green: 0.45, blue: 1.0))
                        .opacity(1 - phase)
                        .offset(x: 26 + phase * 22, y: -40 - phase * 34)
                }
            case nil:
                if waterDue {
                    Text("💧").font(.system(size: 22))
                        .offset(x: -46, y: -34 + sin(t * 4) * 5)
                }
            }
            if let emoji = reminderEmoji {
                Text(emoji).font(.system(size: 22))
                    .offset(x: -44, y: 2 + sin(t * 3 + 1) * 5)
            }
            if remote {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(mood.color.opacity(0.6 + 0.4 * sin(t * 3)))
                    .offset(x: 22, y: -62)
            }
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(alert ? Color.red : Mood.working.color))
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 46, y: -40)
            }
        }
        .offset(y: 8)
        .frame(width: 130, height: 150)
    }

    private func figure(t: Double) -> some View {
        let bob: Double = switch mood {
        case .idle: sin(t * 2) * 3
        case .working: sin(t * 7) * 2.5
        case .waiting: sin(t * 1.5) * 1.5
        case .celebrating: -abs(sin(t * 6)) * 16
        case .stretching: -abs(sin(t * 1.2)) * 6
        }
        let tilt: Double = mood == .waiting ? sin(t * 2.2) * 9
            : mood == .idle ? sin(t * 0.8) * 3
            : mood == .stretching ? sin(t * 1.2) * 12 : 0

        return ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: 60 + bob * 1.2, height: 9)
                .offset(y: 60)
            ZStack {
                arms(t: t)
                torso
                head(t: t)
            }
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .offset(y: bob)
            extras(t: t)
            if remote {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(mood.color.opacity(0.6 + 0.4 * sin(t * 3)))
                    .offset(x: 18, y: -70 + bob)
            }
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(alert ? Color.red : Mood.working.color))
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 44, y: -48 + bob)
            }
        }
        .offset(y: 8)
        .frame(width: 130, height: 150)
    }

    private func arms(t: Double) -> some View {
        let (left, right): (Double, Double) = switch mood {
        case .idle: (10 + sin(t * 1.5) * 6, -10 - sin(t * 1.5) * 6)
        case .working: (15 + sin(t * 14) * 18, -15 + sin(t * 14) * 18)
        case .waiting: (12, -150 + sin(t * 6) * 12)
        case .celebrating: (150 + sin(t * 12) * 15, -150 - sin(t * 12) * 15)
        case .stretching: (165 + sin(t * 1.2) * 10, -165 + sin(t * 1.2) * 10)
        }
        return ZStack {
            arm.rotationEffect(.degrees(left), anchor: .top).offset(x: -31, y: 41)
            arm.rotationEffect(.degrees(right), anchor: .top).offset(x: 31, y: 41)
        }
    }

    private var arm: some View {
        Capsule().fill(shell).overlay(Capsule().stroke(outline, lineWidth: 1.5)).frame(width: 12, height: 30)
    }

    private var torso: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(shell)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(outline, lineWidth: 1.5))
            .overlay(Circle().fill(mood.color).frame(width: 10, height: 10).offset(y: 4))
            .frame(width: 54, height: 34)
            .offset(y: 36)
    }

    private func head(t: Double) -> some View {
        let pulse = mood == .waiting ? 0.5 + 0.5 * sin(t * 8) : 0.6 + 0.4 * sin(t * 2.5)
        return ZStack {
            // Antenna
            Rectangle().fill(outline).frame(width: 3, height: 14).offset(y: -56)
            Circle().fill(mood.color).frame(width: 13, height: 13)
                .shadow(color: mood.color.opacity(pulse), radius: 4 + 6 * pulse)
                .offset(y: -66)
            // Ears
            Capsule().fill(mood.color).frame(width: 8, height: 22).offset(x: -48, y: -14)
            Capsule().fill(mood.color).frame(width: 8, height: 22).offset(x: 48, y: -14)
            // Head shell
            RoundedRectangle(cornerRadius: 24)
                .fill(shell)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(outline, lineWidth: 1.5))
                .frame(width: 92, height: 70)
                .offset(y: -14)
            Capsule().fill(Color.white.opacity(0.9)).frame(width: 16, height: 5).rotationEffect(.degrees(-20))
                .offset(x: -30, y: -42)
            // Face screen
            RoundedRectangle(cornerRadius: 16).fill(screen).frame(width: 72, height: 48).offset(y: -14)
            eyes(t: t)
            mouth(t: t)
            Circle().fill(Color.pink.opacity(0.55)).frame(width: 8, height: 8).offset(x: -26, y: -4)
            Circle().fill(Color.pink.opacity(0.55)).frame(width: 8, height: 8).offset(x: 26, y: -4)
        }
    }

    @ViewBuilder
    private func eyes(t: Double) -> some View {
        if mood == .celebrating || mood == .stretching {
            ForEach([-15.0, 15.0], id: \.self) { x in
                Arc(up: true).stroke(eyeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 13, height: 6).offset(x: x, y: -20)
            }
        } else {
            let blink = t.truncatingRemainder(dividingBy: 3.6) < 0.13
            let look = mood == .working ? sin(t * 2.5) * 4 : 0
            let size: CGFloat = mood == .waiting ? 13 : 10
            ForEach([-15.0, 15.0], id: \.self) { x in
                Capsule().fill(eyeColor)
                    .frame(width: size, height: size + 4)
                    .scaleEffect(x: 1, y: blink ? 0.1 : 1)
                    .shadow(color: eyeColor.opacity(0.8), radius: 3)
                    .offset(x: x + look, y: -19)
            }
        }
    }

    @ViewBuilder
    private func mouth(t: Double) -> some View {
        switch mood {
        case .idle:
            Arc(up: false).stroke(eyeColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 16, height: 4).offset(y: -4)
        case .working:
            Capsule().fill(eyeColor).frame(width: 8 + abs(sin(t * 9)) * 6, height: 3).offset(y: -2)
        case .waiting:
            Circle().stroke(eyeColor, lineWidth: 2.5).frame(width: 8, height: 8).offset(y: -2)
        case .celebrating:
            Arc(up: false).fill(Color(red: 1.0, green: 0.45, blue: 0.6))
                .frame(width: 20, height: 7).offset(y: -5)
        case .stretching:
            Capsule().fill(eyeColor).frame(width: 10, height: 4 + abs(sin(t * 1.2)) * 5).offset(y: -3)
        }
    }

    @ViewBuilder
    private func extras(t: Double) -> some View {
        switch mood {
        case .working:
            Image(systemName: "gearshape.fill").font(.system(size: 20)).foregroundStyle(mood.color)
                .rotationEffect(.degrees(t * 120)).offset(x: -50, y: -56)
            Image(systemName: "gearshape.fill").font(.system(size: 13)).foregroundStyle(mood.color.opacity(0.8))
                .rotationEffect(.degrees(-t * 180)).offset(x: -36, y: -70)
        case .waiting:
            Text("?").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(mood.color)
                .offset(x: -48, y: -58 + sin(t * 5) * 4)
        case .celebrating:
            let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
            ForEach(0..<16, id: \.self) { i in
                let d = Double(i)
                let phase = (t * 0.9 + d * 0.137).truncatingRemainder(dividingBy: 1)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(palette[i % palette.count])
                    .frame(width: 5, height: 9)
                    .rotationEffect(.degrees(t * 220 + d * 40))
                    .offset(x: sin(d * 12.9898) * 58 + sin(t * 3 + d) * 6, y: -80 + phase * 140)
                    .opacity(1 - phase)
            }
        case .stretching:
            Text("💧").font(.system(size: 20)).offset(x: -50, y: -40 + sin(t * 2) * 5)
            Text("z").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(mood.color.opacity(0.7))
                .offset(x: -40, y: -66 + sin(t * 1.5) * 3)
        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Bubble & task list

struct SpeechBubble: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 260, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.7), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

struct DeployRow: View {
    let run: DeployRun
    let now: Date
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if run.isActive {
                    ProgressView().controlSize(.small)
                } else if run.conclusion == "success" {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Mood.celebrating.color)
                } else if run.conclusion == "cancelled" || run.conclusion == "skipped" {
                    Image(systemName: "stop.circle.fill").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(Mood.waiting.color)
                }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(run.repoName).font(.system(size: 12, weight: .semibold))
                    Text(run.branch).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Text(run.isActive ? formatDuration(now.timeIntervalSince(run.created))
                                      : formatDuration(now.timeIntervalSince(run.updated)) + " ago")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(run.workflow).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .contentShape(Rectangle())
        .onTapGesture { if let u = URL(string: run.url) { NSWorkspace.shared.open(u) } }
        .help("Open on GitHub")
    }
}

struct RequestCard: View {
    let request: PendingRequest
    @ObservedObject var tracker: Tracker
    @ObservedObject var draft: CardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch request.kind {
            case let .permission(tool, summary):
                Text("🔐 \(request.project) wants to use \(tool)").font(.system(size: 13, weight: .bold, design: .rounded))
                if !summary.isEmpty { codeBox(summary) }
                HStack {
                    Button("Use terminal") { tracker.answer(request, ["action": "release"]) }
                        .buttonStyle(.borderless).font(.system(size: 11))
                    Spacer()
                    Button("Deny") { tracker.answer(request, ["action": "deny"]) }
                    Button("Allow") { tracker.answer(request, ["action": "allow"]) }
                        .buttonStyle(.borderedProminent).tint(Mood.celebrating.color)
                }

            case let .questions(questions):
                Text("❓ \(request.project) is asking").font(.system(size: 13, weight: .bold, design: .rounded))
                ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                    questionView(i, q)
                }
                HStack {
                    Button("Use terminal") { tracker.answer(request, ["action": "release"]) }
                        .buttonStyle(.borderless).font(.system(size: 11))
                    Spacer()
                    Button("Send answers") { submit(questions) }
                        .buttonStyle(.borderedProminent).tint(Mood.idle.color)
                        .disabled(!questions.indices.allSatisfy { answerFor($0, questions[$0]) != nil })
                }

            case let .reply(lastMessage):
                Text("💬 \(request.project) finished. Reply?").font(.system(size: 13, weight: .bold, design: .rounded))
                if !lastMessage.isEmpty {
                    ScrollView { Text(lastMessage).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                        .frame(maxHeight: 110)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                }
                TextField("Reply to \(request.project)…", text: $draft.text, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder).font(.system(size: 12))
                    .onSubmit(sendReply)
                HStack {
                    Button("Done") { tracker.answer(request, ["action": "release"]) }
                        .buttonStyle(.borderless).font(.system(size: 11))
                    Spacer()
                    Button("Send", action: sendReply)
                        .buttonStyle(.borderedProminent).tint(Mood.idle.color)
                        .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Mood.waiting.color.opacity(0.7), lineWidth: 1.2))
    }

    private func codeBox(_ s: String) -> some View {
        Text(s).font(.system(size: 11, design: .monospaced)).lineLimit(8).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    private func questionView(_ i: Int, _ q: AgentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(q.text).font(.system(size: 12, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            ForEach(q.options, id: \.self) { opt in
                let on = draft.picks[i, default: []].contains(opt)
                Button {
                    var set = q.multi ? draft.picks[i, default: []] : []
                    if on { set.remove(opt) } else { set.insert(opt) }
                    draft.picks[i] = set
                } label: {
                    HStack {
                        Image(systemName: on ? (q.multi ? "checkmark.square.fill" : "largecircle.fill.circle")
                                             : (q.multi ? "square" : "circle"))
                        Text(opt).font(.system(size: 12)).multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            TextField("Other…", text: Binding(get: { draft.other[i] ?? "" }, set: { draft.other[i] = $0 }))
                .textFieldStyle(.roundedBorder).font(.system(size: 12))
        }
    }

    private func answerFor(_ i: Int, _ q: AgentQuestion) -> Any? {
        let typed = (draft.other[i] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = q.options.filter { draft.picks[i, default: []].contains($0) }
        if q.multi {
            let all = chosen + (typed.isEmpty ? [] : [typed])
            return all.isEmpty ? nil : all
        }
        return typed.isEmpty ? chosen.first : typed
    }

    private func submit(_ questions: [AgentQuestion]) {
        var answers: [String: Any] = [:]
        for (i, q) in questions.enumerated() { answers[q.text] = answerFor(i, q) }
        tracker.answer(request, ["action": "allow", "answers": answers])
    }

    private func sendReply() {
        let t = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        tracker.answer(request, ["action": "reply", "text": t])
    }
}

/// A plain card used by the smaller "needs you" items.
private struct SimpleCard<Content: View>: View {
    let color: Color
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.7), lineWidth: 1.2))
    }
}

struct UrgentMessagesCard: View {
    @ObservedObject var tracker: Tracker
    var body: some View {
        SimpleCard(color: Mood.waiting.color) {
            Text("📣 From your agents").font(.system(size: 13, weight: .bold, design: .rounded))
            ForEach(tracker.urgentMessages) { m in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.project).font(.system(size: 11, weight: .semibold))
                        Text(m.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    Spacer()
                    Button { withAnimation { tracker.urgentMessages.removeAll { $0.id == m.id } } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
        }
    }
}

struct NapSummaryCard: View {
    @ObservedObject var tracker: Tracker
    var body: some View {
        SimpleCard(color: Mood.stretching.color) {
            Text("😴 While I napped").font(.system(size: 13, weight: .bold, design: .rounded))
            ForEach(Array((tracker.napSummary ?? []).enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 11)).lineLimit(2)
            }
            HStack { Spacer(); Button("Got it") { withAnimation { tracker.napSummary = nil } }.buttonStyle(.borderless).font(.system(size: 11)) }
        }
    }
}

struct YesterdayNoteCard: View {
    @ObservedObject var tracker: Tracker
    var body: some View {
        SimpleCard(color: Mood.idle.color) {
            Text("📝 Your note from last time").font(.system(size: 13, weight: .bold, design: .rounded))
            Text(tracker.yesterdayNote ?? "").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            HStack { Spacer(); Button("Done") { withAnimation { tracker.yesterdayNote = nil } }.buttonStyle(.borderless).font(.system(size: 11)) }
        }
    }
}

struct EndOfDayCard: View {
    @ObservedObject var tracker: Tracker
    @ObservedObject var draft: CardDraft
    var body: some View {
        SimpleCard(color: Color(red: 1.0, green: 0.55, blue: 0.3)) {
            Text("🌇 That's the workday").font(.system(size: 13, weight: .bold, design: .rounded))
            ScrollView {
                Text(tracker.today.summary()).font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(maxHeight: 150)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            Button("Copy for standup") { tracker.copySummary() }.buttonStyle(.borderless).font(.system(size: 11))
            Text("Leave yourself a note for tomorrow: where you stopped, what's next.")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            TextField("e.g. finish the dev ECS fix, then review #1502", text: $draft.text, axis: .vertical)
                .lineLimit(1...4).textFieldStyle(.roundedBorder).font(.system(size: 12))
            HStack {
                Button("Not today") { tracker.saveNote("") }.buttonStyle(.borderless).font(.system(size: 11))
                Spacer()
                Button("Save note") { tracker.saveNote(draft.text) }
                    .buttonStyle(.borderedProminent).tint(Color(red: 1.0, green: 0.55, blue: 0.3))
            }
        }
    }
}

/// Collapsible header shared by the panel's sections.
struct SectionHeader<Trailing: View>: View {
    @ObservedObject var tracker: Tracker
    let key: String
    let title: String
    @ViewBuilder let trailing: Trailing
    var body: some View {
        let closed = tracker.closedSections.contains(key)
        Button { tracker.toggle(key, in: \.closedSections) } label: {
            HStack(spacing: 4) {
                Image(systemName: closed ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .bold))
                sectionHeader(title)
                Spacer()
                trailing
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PRSection: View {
    @ObservedObject var tracker: Tracker
    var body: some View {
        let closed = tracker.closedSections.contains("prs")
        let failing = tracker.prs.filter { $0.checks == .failing }.count
        let ready = tracker.prs.filter(\.readyToMerge).count
        VStack(alignment: .leading, spacing: 5) {
            SectionHeader(tracker: tracker, key: "prs", title: "Pull requests") {
                if closed {
                    Text(failing > 0 ? "❌ \(failing) failing" : ready > 0 ? "✅ \(ready) ready" : "\(tracker.prs.count) open")
                        .font(.system(size: 10)).foregroundStyle(failing > 0 ? Mood.waiting.color : .secondary)
                }
            }
            if !closed {
                if PRWatcher.gh == nil {
                    Text("Install GitHub's gh to see your PRs.").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if tracker.prs.isEmpty && tracker.reviewPRs.isEmpty {
                    Text("No open PRs.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(tracker.prs) { pr in row(pr, mine: true) }
                if !tracker.reviewPRs.isEmpty {
                    Text("Waiting for your review").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 2)
                    ForEach(tracker.reviewPRs) { pr in row(pr, mine: false) }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private func row(_ pr: PullRequest, mine: Bool) -> some View {
        let checksColor: Color = switch pr.checks {
        case .failing: Mood.waiting.color
        case .pending: Mood.working.color
        case .passing: Mood.celebrating.color
        case .none: .secondary
        }
        let color = mine ? checksColor : Mood.idle.color
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text("\(pr.repoName) #\(pr.number)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                Text(pr.title).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 4)
                if pr.isDraft { tag("draft", .secondary) }
                if pr.mergeable == "CONFLICTING" { tag("conflict", Mood.waiting.color) }
                if pr.review == "APPROVED" { tag("approved", Mood.celebrating.color) }
                if pr.review == "CHANGES_REQUESTED" { tag("changes", Mood.working.color) }
            }
            .contentShape(Rectangle())
            .onTapGesture { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } }
            .help("Open on GitHub")
            if mine && pr.checks == .failing {
                VStack(alignment: .leading, spacing: 3) {
                    if let err = pr.ciError {
                        Text(err).font(.system(size: 10, design: .monospaced)).foregroundStyle(Mood.waiting.color)
                            .lineLimit(2).textSelection(.enabled)
                    }
                    if let id = pr.agentId, let agent = tracker.tasks.first(where: { $0.id == id }) {
                        Button("Send to \(agent.project) to fix") { tracker.sendPRFix(pr) }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Mood.idle.color)
                    } else if !pr.headRef.isEmpty {
                        Text("No local agent on \(pr.headRef)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 13)
            }
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

struct HousekeepingSection: View {
    @ObservedObject var tracker: Tracker
    var body: some View {
        let h = tracker.housekeeping
        let closed = tracker.closedSections.contains("housekeeping")
        VStack(alignment: .leading, spacing: 5) {
            SectionHeader(tracker: tracker, key: "housekeeping", title: "Housekeeping") {
                Text(String(format: "%.0f GB free", h.freeGB)).font(.system(size: 10))
                    .foregroundStyle(h.lowDisk ? Mood.waiting.color : .secondary)
            }
            if !closed {
                if h.lowDisk {
                    Text(String(format: "💾 Only %.0f GB of %.0f GB free.", h.freeGB, h.totalGB))
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Mood.waiting.color)
                }
                if !h.bigLogs.isEmpty {
                    Text("Huge dev logs").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(h.bigLogs) { item(path: $0.path, detail: $0.detail) }
                }
                if !h.staleWorktrees.isEmpty {
                    Text("Worktrees untouched for 2+ weeks").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(h.staleWorktrees) { item(path: $0.path, detail: $0.detail) }
                }
                if !h.prunable.isEmpty {
                    Text("Leftover worktree entries").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(h.prunable) { item(path: $0.path, detail: $0.detail) }
                }
                Text("I only report these; nothing is deleted.").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private func item(path: String, detail: String) -> some View {
        let short = tracker.projectRoots.map { NSString(string: $0).expandingTildeInPath + "/" }
            .reduce(path) { $0.replacingOccurrences(of: $1, with: "") }
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return HStack(spacing: 6) {
            Text(short).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            Button { tracker.reveal(path) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).help("Show in Finder")
        }
    }
}

struct ReminderCard: View {
    @ObservedObject var tracker: Tracker
    let reminder: DailyReminder
    private let orange = Color(red: 1.0, green: 0.58, blue: 0.2)
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(reminder.emoji ?? "⏰") \(reminder.title)").font(.system(size: 13, weight: .bold, design: .rounded))
            Text(reminder.message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Snooze 15 min") { tracker.snoozeReminder(minutes: 15) }
                    .buttonStyle(.borderless).font(.system(size: 11))
                Spacer()
                Button("Dismiss") { tracker.dismissReminder(tookBreak: false) }
                    .buttonStyle(.borderless).font(.system(size: 11))
                Button(reminder.activity == "eat" ? "Going for lunch"
                       : reminder.activity == "sleep" ? "Going to sleep" : "Taking it now") {
                    tracker.dismissReminder(tookBreak: true)
                }
                    .buttonStyle(.borderedProminent).tint(orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(orange.opacity(0.7), lineWidth: 1.2))
    }
}

struct WaterCard: View {
    @ObservedObject var tracker: Tracker
    private let blue = Color(red: 0.33, green: 0.68, blue: 0.98)
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💧 Time to drink some water").font(.system(size: 13, weight: .bold, design: .rounded))
            Text("Another hour has gone by. Take a glass of water.")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Snooze 15 min") { tracker.snoozeWater(minutes: 15) }
                    .buttonStyle(.borderless).font(.system(size: 11))
                Spacer()
                Button("I drank water") { tracker.drankWater() }
                    .buttonStyle(.borderedProminent).tint(blue)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(blue.opacity(0.7), lineWidth: 1.2))
    }
}

struct BreakCard: View {
    @ObservedObject var tracker: Tracker
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🧘 Time for a break").font(.system(size: 13, weight: .bold, design: .rounded))
            Text("You've been working for \(formatDuration(tracker.workedFor)). Stand up, stretch, look away from the screen, and drink some water. Your agents will keep going.")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Snooze 30 min") { tracker.snoozeBreaks(minutes: 30) }
                    .buttonStyle(.borderless).font(.system(size: 11))
                Spacer()
                Button("I took a break") { tracker.tookBreak() }
                    .buttonStyle(.borderedProminent).tint(Mood.stretching.color)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Mood.stretching.color.opacity(0.7), lineWidth: 1.2))
    }
}

struct CloudSection: View {
    @ObservedObject var tracker: Tracker
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 4, alignment: .leading)]

    var body: some View {
        let closed = tracker.closedSections.contains("cloud")
        VStack(alignment: .leading, spacing: 6) {
            Button { tracker.toggle("cloud", in: \.closedSections) } label: {
                HStack(spacing: 4) {
                    Image(systemName: closed ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .bold))
                    sectionHeader("Cloud")
                    Spacer()
                    if closed { Text(cloudSummary).font(.system(size: 10)).foregroundStyle(cloudSummaryColor) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !closed {
            // AWS ECS
            Group {
                if tracker.aws.isLoggedOut {
                    note("AWS ECS: log in to AWS to see your services.")
                } else if tracker.ecs.isEmpty {
                    note(tracker.ecsProblems.first.map { "AWS ECS: \($0)" } ?? "AWS ECS: checking…")
                } else {
                    ForEach(Dictionary(grouping: tracker.ecs, by: \.cluster).sorted { $0.key < $1.key }, id: \.key) { cluster, services in
                        clusterView(cluster, services)
                    }
                }
            }
            // Codex Cloud
            if CodexCloud.bin != nil {
                if !tracker.codexSignedIn {
                    HStack {
                        note("Codex cloud: not signed in.")
                        Button("Sign in") { tracker.codexLogin() }.buttonStyle(.borderless).font(.system(size: 11))
                    }
                } else if tracker.codexCloud.isEmpty {
                    note("Codex cloud: no recent tasks.")
                } else {
                    ForEach(tracker.codexCloud.prefix(6)) { t in
                        HStack(spacing: 6) {
                            Circle().fill(codexColor(t)).frame(width: 7, height: 7)
                            Text(t.title).font(.system(size: 11)).lineLimit(1)
                            Spacer()
                            Text(t.status).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if let u = t.url.flatMap(URL.init(string:)) { NSWorkspace.shared.open(u) } }
                    }
                }
            }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private var cloudSummary: String {
        let down = tracker.ecs.filter(\.isUnhealthy).count
        let deploying = tracker.ecs.filter(\.deploying).count
        if tracker.ecs.isEmpty { return "" }
        if down > 0 { return "⚠ \(down) down" }
        if deploying > 0 { return "↻ \(deploying) deploying" }
        return "✓ all healthy"
    }
    private var cloudSummaryColor: Color {
        tracker.ecs.contains(where: \.isUnhealthy) ? Mood.waiting.color
            : tracker.ecs.contains(where: \.deploying) ? Mood.working.color : Mood.celebrating.color
    }

    /// A cluster collapses to one summary line; broken services stay visible anyway.
    private func clusterView(_ cluster: String, _ services: [EcsService]) -> some View {
        let open = tracker.openClusters.contains(cluster)
        let down = services.filter(\.isUnhealthy)
        let deploying = services.filter(\.deploying).count
        let (summary, color): (String, Color) =
            !down.isEmpty ? ("⚠ \(down.count) down", Mood.waiting.color)
            : deploying > 0 ? ("↻ \(deploying) deploying", Mood.working.color)
            : ("✓ \(services.count) healthy", Mood.celebrating.color)
        return VStack(alignment: .leading, spacing: 4) {
            Button { tracker.toggle(cluster, in: \.openClusters) } label: {
                HStack(spacing: 4) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(cluster).font(.system(size: 11, weight: .semibold))
                    if services.first?.isProduction == true {
                        Text("prod").font(.system(size: 9, weight: .bold)).foregroundStyle(Mood.waiting.color)
                    }
                    Spacer()
                    Text(summary).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            let shown = open ? services : down
            if !shown.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(shown) { ecsChip($0) }
                }
                .padding(.leading, 13)
            }
            // Why broken services are down, grouped when they share a cause.
            let reasons = Dictionary(grouping: down.filter { $0.stopReason != nil }, by: { $0.stopReason! })
            ForEach(reasons.keys.sorted(), id: \.self) { reason in
                Text("\(reasons[reason]!.map(\.short).joined(separator: ", ")): \(reason)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Mood.waiting.color)
                    .lineLimit(4).textSelection(.enabled)
                    .padding(.leading, 13)
            }
        }
    }

    private func codexColor(_ t: CodexCloudTask) -> Color {
        switch t.state {
        case .working: Mood.working.color
        case .done: Mood.celebrating.color
        case .failed: Mood.waiting.color
        case .other: .secondary
        }
    }

    private func ecsChip(_ s: EcsService) -> some View {
        let color: Color = s.rollout == "FAILED" || (s.running < s.desired && !s.deploying) ? Mood.waiting.color
            : s.deploying ? Mood.working.color : Mood.celebrating.color
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(s.short).font(.system(size: 10)).lineLimit(1)
            Text("\(s.running)/\(s.desired)").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.1)))
        .contentShape(Rectangle())
        .onTapGesture { if let u = s.consoleURL(region: tracker.ecsRegion) { NSWorkspace.shared.open(u) } }
        .help("\(s.name): \(s.running) running, \(s.desired) wanted, \(s.pending) pending"
              + (s.rollout.isEmpty ? "" : " · rollout \(s.rollout)") + "\n\(s.stopReason ?? s.lastEvent)\nClick to open in the AWS console.")
    }
}

struct StackSection: View {
    @ObservedObject var tracker: Tracker
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 4, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Local stack")
            ForEach(tracker.stacks) { stack in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(stack.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text("slot \(stack.slot) · \(stack.env)").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button { tracker.restartStack(stack) } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).help("Restart: runs make debug in Terminal")
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                        ForEach(stack.services) { svc in chip(svc) }
                    }
                    ForEach(stack.services.filter { $0.status == .down || $0.status == .notListening }) { svc in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(svc.name) " + (svc.status == .down ? "stopped" : "isn't answering on port \(svc.port ?? 0)")
                                 + (svc.portOwner.map { ". Port \(svc.port ?? 0) is held by \($0)" } ?? ""))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Mood.waiting.color)
                            if let err = svc.error {
                                Text(err).font(.system(size: 10, design: .monospaced)).lineLimit(3)
                                    .textSelection(.enabled).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 10) {
                                if !svc.logPath.isEmpty {
                                    Button("Open log") { tracker.openLog(svc) }
                                }
                                if !svc.logPath.isEmpty {
                                    Button("Ask an agent to fix") { tracker.askAgentToFix(stack, svc) }
                                }
                            }
                            .buttonStyle(.borderless).font(.system(size: 11))
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Mood.waiting.color.opacity(0.08)))
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            }
            if !tracker.tunnels.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 10))
                    Text("DB tunnels:").font(.system(size: 11))
                    ForEach(tracker.tunnels) { t in
                        Text(t.isProduction ? "\(t.env) ⚠︎" : t.env)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill((t.isProduction ? Mood.waiting.color : Color.secondary).opacity(0.15)))
                            .foregroundStyle(t.isProduction ? Mood.waiting.color : .secondary)
                            .help(t.isProduction ? "Production database tunnel on port \(t.port)" : "Tunnel on port \(t.port)")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func chip(_ svc: StackService) -> some View {
        let color: Color = switch svc.status {
        case .up: Mood.celebrating.color
        case .starting: Mood.working.color
        case .down, .notListening: Mood.waiting.color
        }
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(svc.name).font(.system(size: 10)).lineLimit(1)
            if let port = svc.port { Text("\(port)").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.1)))
        .contentShape(Rectangle())
        .onTapGesture { tracker.openLog(svc) }
        .help(svc.logPath.isEmpty ? "\(svc.name) (docker)" : "Open \(svc.name) log")
    }
}

/// Same for Google Cloud (gcloud). Shown only when gcloud is installed.
struct GcpPill: View {
    @ObservedObject var tracker: Tracker
    var body: some View {
        let (color, help): (Color, String) = switch tracker.gcp {
        case .active(let who): (Mood.celebrating.color, "gcloud logged in as \(who). Click to check again.")
        case .loggedOut(let why): (Mood.waiting.color, "gcloud not logged in: \(why)\nClick to run gcloud auth login.")
        case .unknown: (.secondary, "Google Cloud login status unknown (offline or not checked yet). Click to check.")
        }
        Button {
            if tracker.gcp.isLoggedOut { tracker.loginGcp() } else { tracker.checkGcp() }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(tracker.gcp.isLoggedOut ? "GCP · Log in" : "GCP").font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Green when the AWS CLI is logged in, red when it isn't. Click: log in (or re-check).
struct AwsPill: View {
    @ObservedObject var tracker: Tracker
    var body: some View {
        let (color, help): (Color, String) = switch tracker.aws {
        case .active(let who): (Mood.celebrating.color, "AWS CLI logged in as \(who). Click to check again.")
        case .loggedOut(let why): (Mood.waiting.color, "AWS CLI not logged in: \(why)\nClick to run aws login.")
        case .unknown: (.secondary, "AWS login status unknown (offline or not checked yet). Click to check.")
        }
        Button {
            if tracker.aws.isLoggedOut { tracker.loginAws() } else { tracker.checkAws() }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(tracker.aws.isLoggedOut ? "AWS · Log in" : "AWS").font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private func sectionHeader(_ title: String) -> some View {
    Text(title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
}

extension AnyTransition {
    /// The panel pops out of the robot (bottom-right corner) and folds back into it.
    static var panel: AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity))
    }
}

/// The on-screen root: pins the content to the bottom-right corner, so the
/// robot stays put while the window is briefly bigger than the content.
struct AnchoredRoot: View {
    let tracker: Tracker
    let mover: WindowMover
    var body: some View {
        RootView(tracker: tracker, mover: mover)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

struct RootView: View {
    @ObservedObject var tracker: Tracker
    let mover: WindowMover

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if tracker.expanded, let sid = tracker.chatSession {
                ChatView(tracker: tracker, draft: tracker.chatDraft, sessionId: sid)
                    .environment(\.colorScheme, .dark)
                    .transition(.panel)
            } else if tracker.expanded {
                TaskListView(tracker: tracker)
                    .transition(.panel)
            } else if let text = tracker.bubble {
                SpeechBubble(text: text, color: tracker.mood.color)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                    .onTapGesture { tracker.bubbleTapped() }
            }
            BuddyCharacter(character: tracker.character,
                           mood: tracker.mood,
                           waterDue: tracker.waterDue,
                           reminderEmoji: tracker.dueReminder.flatMap { $0.activity == nil ? ($0.emoji ?? "⏰") : nil },
                           activity: tracker.activity,
                           prod: tracker.prodActive,
                           count: tracker.needsYouCount > 0 ? tracker.needsYouCount : tracker.activeCount,
                           alert: tracker.needsYouCount > 0,
                           remote: tracker.remoteMode)
                .scaleEffect(tracker.scale)
                .frame(width: 130 * tracker.scale, height: 150 * tracker.scale)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in mover.drag() }
                        .onEnded { _ in if !mover.end() { tracker.togglePanel() } }
                )
                .help("Click to show or hide your agents")
                .contextMenu {
                    Button(tracker.expanded ? "Hide panel" : "Show panel") { tracker.togglePanel() }
                    Button("Clear finished tasks") { tracker.clearDone() }
                    Toggle("Remote mode (answer agents here)", isOn: $tracker.remoteMode)
                    Toggle("Also show Mac notifications", isOn: $tracker.macNotifications)
                    Button(tracker.aws.isLoggedOut ? "AWS: log in…" : "AWS: check login now") {
                        if tracker.aws.isLoggedOut { tracker.loginAws() } else { tracker.checkAws() }
                    }
                    Picker("Character", selection: $tracker.character) {
                        ForEach(BuddyCharacterKind.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Bigger") { tracker.resize(by: 0.1) }.disabled(tracker.scale >= 1.2)
                    Button("Smaller") { tracker.resize(by: -0.1) }.disabled(tracker.scale <= 0.3)
                    if tracker.napping {
                        Button("Wake up") { tracker.wake() }
                    } else {
                        Menu("Nap (hold all alerts)") {
                            Button("30 minutes") { tracker.nap(minutes: 30) }
                            Button("1 hour") { tracker.nap(minutes: 60) }
                            Button("2 hours") { tracker.nap(minutes: 120) }
                            Button("Until I wake you") { tracker.nap(minutes: nil) }
                        }
                    }
                    Toggle("Water reminders (hourly)", isOn: $tracker.waterOn)
                    Menu("Break reminders") {
                        Button("I just took a break") { tracker.tookBreak() }
                        Button("Snooze 1 hour") { tracker.snoozeBreaks(minutes: 60) }
                        Button("Snooze 3 hours") { tracker.snoozeBreaks(minutes: 180) }
                    }
                    Divider()
                    Button("Quit Agent Buddy") { NSApp.terminate(nil) }
                }
        }
        .padding(10)
        .fixedSize() // the window is resized to exactly this (see AppDelegate.fitWindow)
    }
}

// MARK: - App

final class BuddyPanel: NSPanel {
    override var canBecomeKey: Bool { true } // so reply text fields can take typing
}

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: BuddyPanel!
    var host: ClickThroughHostingView<AnchoredRoot>!
    let tracker = Tracker()
    let mover = WindowMover()
    private var sizeWatch: AnyCancellable?

    /// Shrinks/grows the window to whatever is showing, so it never covers or
    /// blocks clicks on the screen behind it.
    func fitWindow() {
        mover.fit(measurer.sizeThatFits(in: CGSize(width: 4000, height: 4000)))
    }
    /// An off-screen copy of the view, used only to measure its size (the
    /// on-screen hosting view reports zero once SwiftUI sizing is turned off).
    lazy var measurer = NSHostingController(rootView: AnyView(
        RootView(tracker: tracker, mover: mover).environment(\.isMeasuring, true)))

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 100, height: 100) // resized to the content right away
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var anchor = NSPoint(x: visible.maxX - 8, y: visible.minY + 8) // bottom-right corner
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "anchor") {
            anchor = NSPointFromString(saved)
        } else if let old = defaults.string(forKey: "origin") {
            // Older versions saved the origin of a fixed 340-wide window.
            let o = NSPointFromString(old)
            anchor = NSPoint(x: o.x + 340, y: o.y)
        }
        // Keep the robot on a screen that exists (displays can change).
        let robot = NSRect(x: anchor.x - 90, y: anchor.y, width: 90, height: 100)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(robot) }) {
            anchor = NSPoint(x: visible.maxX - 8, y: visible.minY + 8)
        }
        let origin = NSPoint(x: anchor.x - size.width, y: anchor.y)

        panel = BuddyPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        mover.window = panel // before the first layout, so the first fit() can size the window
        host = ClickThroughHostingView(rootView: AnchoredRoot(tracker: tracker, mover: mover))
        host.sizingOptions = [] // the window is sized by WindowMover.fit, not by SwiftUI constraints
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()

        tracker.start()
        // Any state change can change what's showing; measure after SwiftUI applies it.
        sizeWatch = tracker.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fitWindow() }
        }
        DispatchQueue.main.async { self.fitWindow() }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
