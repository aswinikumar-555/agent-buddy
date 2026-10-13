// The panel that opens when you click the buddy: design "A · Tabs" with the
// status pills from "B · Inbox". Header (AWS, remote, settings), four number
// tiles, tabs (Agents · Code · Cloud · Me), and status pills at the bottom.
import AppKit
import SwiftUI

enum PanelTab: String, CaseIterable {
    case agents = "Agents", code = "Code", cloud = "Cloud", me = "Me"
}

/// A color scheme for the panel (⚙︎ → Theme). "Auto" follows the Mac's light/dark setting.
struct PanelTheme {
    let name: String
    let isDark: Bool
    let bg, border, text, muted, faint, raised, well, segment, pill, pillText: UInt32
    let red, redText, orange, green, blue: UInt32
    let needBg, needLabel, runBg, runNumber, runLabel, neutralBg, neutralLabel: UInt32
    let alertBg, alertBorder, alertText, divider: UInt32

    static let midnight = PanelTheme(
        name: "Midnight", isDark: true,
        bg: 0x17181D, border: 0x2A2C34, text: 0xECEDF2, muted: 0x8D91A3, faint: 0x6F7385, raised: 0x1D1F26,
        well: 0x0F1014, segment: 0x2A2C35, pill: 0x22242B, pillText: 0xD6D8E0,
        red: 0xFF4D6D, redText: 0xFF7A90, orange: 0xFF9F1C, green: 0x29C987, blue: 0x5B8CFF,
        needBg: 0x3A1E27, needLabel: 0xE9B6C0, runBg: 0x3A2C17, runNumber: 0xFFB44D, runLabel: 0xE7CDA3,
        neutralBg: 0x1E2433, neutralLabel: 0xA9B2C8,
        alertBg: 0x22161B, alertBorder: 0x4A2531, alertText: 0xF2C7CF, divider: 0x23252D)

    static let daylight = PanelTheme(
        name: "Daylight", isDark: false,
        bg: 0xF7F8FA, border: 0xDCDFE7, text: 0x1B1E2B, muted: 0x5E6479, faint: 0x868CA0, raised: 0xECEEF3,
        well: 0xE4E7EE, segment: 0xFFFFFF, pill: 0xE9ECF2, pillText: 0x2A2D38,
        red: 0xE5364F, redText: 0xC4223B, orange: 0xD97B00, green: 0x13A26B, blue: 0x3767DB,
        needBg: 0xFCE4E8, needLabel: 0x9A3A48, runBg: 0xFDEFD9, runNumber: 0xB36400, runLabel: 0x82561A,
        neutralBg: 0xE6EBF4, neutralLabel: 0x55607A,
        alertBg: 0xFFF0F2, alertBorder: 0xF1B5BF, alertText: 0x8E2235, divider: 0xE1E4EB)

    static let ocean = PanelTheme(
        name: "Ocean", isDark: true,
        bg: 0x0F1B2A, border: 0x1F3248, text: 0xE6EEF7, muted: 0x8FA3BA, faint: 0x6A7F96, raised: 0x152538,
        well: 0x0A1420, segment: 0x1F3550, pill: 0x182A40, pillText: 0xCFDCEA,
        red: 0xFF5C77, redText: 0xFF8A9C, orange: 0xFFAE42, green: 0x34D399, blue: 0x60A5FA,
        needBg: 0x3A1E2E, needLabel: 0xF0B8C6, runBg: 0x33301C, runNumber: 0xFFC560, runLabel: 0xE8D6A8,
        neutralBg: 0x173049, neutralLabel: 0xA6BDD6,
        alertBg: 0x23172A, alertBorder: 0x4C2840, alertText: 0xF3C6D2, divider: 0x1C2E43)

    static let sunset = PanelTheme(
        name: "Sunset", isDark: true,
        bg: 0x1E1715, border: 0x3A2B25, text: 0xF5ECE6, muted: 0xB39C8F, faint: 0x8C7769, raised: 0x271E1A,
        well: 0x15100E, segment: 0x3A2C25, pill: 0x2D221D, pillText: 0xEADBD1,
        red: 0xFF5A5F, redText: 0xFF8A80, orange: 0xFFB347, green: 0x5CCB8A, blue: 0x7AA7FF,
        needBg: 0x44201F, needLabel: 0xF1BDB5, runBg: 0x45301A, runNumber: 0xFFC069, runLabel: 0xEBD2AE,
        neutralBg: 0x2F2621, neutralLabel: 0xC9B4A6,
        alertBg: 0x2A1916, alertBorder: 0x58302A, alertText: 0xF6CDC6, divider: 0x33261F)

    static let all = [midnight, daylight, ocean, sunset]

    /// The chosen theme ("Auto" picks Midnight or Daylight from the Mac's appearance).
    nonisolated(unsafe) static var choice = UserDefaults.standard.string(forKey: "panelTheme") ?? "Auto"
    static var current: PanelTheme {
        if let t = all.first(where: { $0.name == choice }) { return t }
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? midnight : daylight
    }
}

/// The panel's colors, from the current theme.
enum Palette {
    private static var t: PanelTheme { PanelTheme.current }
    static var bg: Color { Color(hex: t.bg) }
    static var border: Color { Color(hex: t.border) }
    static var text: Color { Color(hex: t.text) }
    static var muted: Color { Color(hex: t.muted) }
    static var faint: Color { Color(hex: t.faint) }
    static var raised: Color { Color(hex: t.raised) }
    static var well: Color { Color(hex: t.well) }
    static var segment: Color { Color(hex: t.segment) }
    static var pill: Color { Color(hex: t.pill) }
    static var pillText: Color { Color(hex: t.pillText) }
    static var red: Color { Color(hex: t.red) }
    static var redText: Color { Color(hex: t.redText) }
    static var orange: Color { Color(hex: t.orange) }
    static var green: Color { Color(hex: t.green) }
    static var blue: Color { Color(hex: t.blue) }
    static var needBg: Color { Color(hex: t.needBg) }
    static var needLabel: Color { Color(hex: t.needLabel) }
    static var runBg: Color { Color(hex: t.runBg) }
    static var runNumber: Color { Color(hex: t.runNumber) }
    static var runLabel: Color { Color(hex: t.runLabel) }
    static var neutralBg: Color { Color(hex: t.neutralBg) }
    static var neutralLabel: Color { Color(hex: t.neutralLabel) }
    static var alertBg: Color { Color(hex: t.alertBg) }
    static var alertBorder: Color { Color(hex: t.alertBorder) }
    static var alertText: Color { Color(hex: t.alertText) }
    static var divider: Color { Color(hex: t.divider) }
    static var scheme: ColorScheme { t.isDark ? .dark : .light }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

func eyebrow(_ text: String, color: Color = Palette.muted) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(color)
}

struct TaskListView: View {
    @ObservedObject var tracker: Tracker

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if tracker.prodActive { prodBanner }
                tiles
                if !tracker.panelCompact { tabs }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, tracker.panelCompact ? 14 : 10)

            if !tracker.panelCompact {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(alignment: .leading, spacing: 14) {
                        switch tracker.panelTab {
                        case .agents: AgentsTab(tracker: tracker, now: ctx.date)
                        case .code: CodeTab(tracker: tracker, now: ctx.date)
                        case .cloud:
                            if tracker.on(.sites) { SitesSection(tracker: tracker) }
                            if tracker.on(.ecs) || tracker.on(.codexCloud) { CloudSection(tracker: tracker) }
                            if tracker.on(.gcp) && !tracker.gcpProjects.isEmpty { CloudRunSection(tracker: tracker) }
                        case .me: MeTab(tracker: tracker, now: ctx.date)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: tracker.panelHeight)
            }

            StatusPills(tracker: tracker)
        }
        .frame(width: tracker.panelWidth)
        .foregroundStyle(Palette.text)
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.bg))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topLeading) { ResizeHandles(tracker: tracker) }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
        .environment(\.colorScheme, Palette.scheme)
    }

    // MARK: Header

    /// Fits the width you've set: drops the title (then "Off duty") rather than wrapping.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(title: true, offDuty: true)
            headerRow(title: true, offDuty: false)
            headerRow(title: false, offDuty: false)
        }
    }

    private func headerRow(title: Bool, offDuty: Bool) -> some View {
        HStack(spacing: 8) {
            if title {
                Text("Agent Buddy").font(.system(size: 16, weight: .semibold)).lineLimit(1).fixedSize()
            }
            if offDuty && tracker.offDuty {
                Text("Off duty").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Palette.pill))
                    .fixedSize()
                    .help("Outside your work hours (\(tracker.workHours.start)–\(tracker.workHours.end)): work alerts are quiet")
            }
            Spacer(minLength: 4)
            if tracker.on(.aws) { AwsPill(tracker: tracker).fixedSize() }
            if tracker.on(.gcp) && Gcp.available { GcpPill(tracker: tracker).fixedSize() }
            Button { tracker.autoRemoteOn = false; tracker.remoteMode.toggle() } label: {
                Text(tracker.remoteMode ? "Remote on" : "Remote off")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(tracker.remoteMode ? Palette.blue.opacity(0.25) : Palette.pill))
                    .foregroundStyle(tracker.remoteMode ? Palette.blue : Palette.muted)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Remote mode: agents wait for your answers here instead of the terminal")
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tracker.panelCompact.toggle() }
            } label: {
                Image(systemName: tracker.panelCompact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tracker.panelCompact ? "Show everything" : "Minimize: just the numbers and status")
            settingsMenu
            Button { tracker.closePanel() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close (or click the buddy)")
        }
    }

    private var settingsMenu: some View {
        Menu {
            Button("Bigger buddy") { tracker.resize(by: 0.1) }.disabled(tracker.scale >= 1.2)
            Button("Smaller buddy") { tracker.resize(by: -0.1) }.disabled(tracker.scale <= 0.3)
            Picker("Character", selection: $tracker.character) {
                ForEach(BuddyCharacterKind.allCases) { Text($0.title).tag($0) }
            }
            Picker("Theme", selection: $tracker.panelTheme) {
                Text("Auto (follow the Mac)").tag("Auto")
                ForEach(PanelTheme.all, id: \.name) { Text($0.name).tag($0.name) }
            }
            Button("Reset panel size") { tracker.resetPanelSize() }
            Divider()
            Button("Clear finished agents") { tracker.clearDone() }
            Menu("Features") {
                ForEach(Feature.Group.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(Feature.allCases.filter { $0.group == group }) { f in
                            Toggle(f.title, isOn: Binding(get: { tracker.on(f) }, set: { tracker.setFeature(f, $0) }))
                        }
                    }
                }
            }
            Toggle("Also show Mac notifications", isOn: $tracker.macNotifications)
            Divider()
            if tracker.napping {
                Button("Wake up") { tracker.wake() }
            } else {
                Button("Nap 1 hour") { tracker.nap(minutes: 60) }
                Button("Nap until I wake you") { tracker.nap(minutes: nil) }
            }
            Divider()
            Button("Quit Agent Buddy") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(Palette.muted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }

    private var prodBanner: some View {
        let reasons = tracker.prodReasons
        return VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { tracker.prodBannerOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                    Text("Production").font(.system(size: 12, weight: .bold))
                    Text("· \(reasons.count) reason\(reasons.count == 1 ? "" : "s")").font(.system(size: 12))
                    Spacer()
                    Image(systemName: tracker.prodBannerOpen ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Palette.redText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if tracker.prodBannerOpen {
                ForEach(Array(reasons.prefix(4).enumerated()), id: \.offset) { _, reason in
                    Text(reason).font(.system(size: 11)).foregroundStyle(Palette.alertText).lineLimit(2)
                }
                Button("Dismiss these commands") { tracker.prodCommands.removeAll() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.needBg))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.red.opacity(0.6), lineWidth: 1))
    }

    // MARK: Number tiles

    private var tiles: some View {
        let failingPRs = tracker.prs.filter { $0.checks == .failing }.count
        let ecsDown = tracker.cloudDownCount
        return HStack(spacing: 6) {
            tile(tracker.panelNeedsYou, "need you", alert: tracker.panelNeedsYou > 0,
                 tint: Palette.needBg, number: Palette.redText, label: Palette.needLabel) { tracker.show(.agents) }
            tile(tracker.runningAgents.count, "running", alert: false,
                 tint: Palette.runBg, number: Palette.runNumber, label: Palette.runLabel) { tracker.show(.agents) }
            tile(failingPRs, "PRs failing", alert: failingPRs > 0,
                 tint: Palette.neutralBg, number: failingPRs > 0 ? Palette.redText : Palette.text, label: Palette.neutralLabel) {
                tracker.show(.code)
            }
            tile(ecsDown, "cloud down", alert: ecsDown > 0,
                 tint: Palette.neutralBg, number: ecsDown > 0 ? Palette.redText : Palette.text, label: Palette.neutralLabel) {
                tracker.show(.cloud)
            }
        }
    }

    private func tile(_ n: Int, _ label: String, alert: Bool, tint: Color, number: Color, label labelColor: Color,
                      action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { action() } }) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(n)").font(.system(size: 20, weight: .semibold).monospacedDigit()).foregroundStyle(number)
                Text(label).font(.system(size: 11)).foregroundStyle(labelColor).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(n == 0 && !alert ? 0.55 : 1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                let on = tracker.panelTab == tab
                Button { withAnimation(.easeInOut(duration: 0.15)) { tracker.panelTab = tab } } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Palette.text : Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Palette.segment : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.well))
    }
}

// MARK: - Agents tab

struct AgentRow: View {
    let task: AgentTask
    let now: Date
    let highlighted: Bool
    let onTap: () -> Void

    var body: some View {
        let color: Color = switch task.state {
        case .working: Palette.orange
        case .waiting: Palette.red
        case .done: Palette.green
        }
        let subtitle = task.state == .done ? (task.summary ?? task.prompt) : task.prompt
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(task.project).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if task.subagents > 0 {
                        Text("+\(task.subagents) sub-agent\(task.subagents == 1 ? "" : "s")")
                            .font(.system(size: 10)).foregroundStyle(Palette.faint)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .lineLimit(task.state == .done ? 2 : 1)
                }
            }
            Spacer(minLength: 6)
            Text(time).font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.faint)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(highlighted ? Palette.raised : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .help("Open chat with this agent")
    }

    private var time: String {
        if task.state == .done, let f = task.finished {
            return task.isHerdrOnly ? "idle" : formatDuration(now.timeIntervalSince(f)) + " ago"
        }
        return formatDuration(now.timeIntervalSince(task.started))
    }
}

struct AgentsTab: View {
    @ObservedObject var tracker: Tracker
    let now: Date

    var body: some View {
        let running = tracker.runningAgents
        let done = tracker.doneAgents
        let idle = tracker.tasks.filter { $0.isHerdrOnly && $0.state == .done }

        if tracker.panelNeedsYou > 0 {
            VStack(alignment: .leading, spacing: 8) {
                eyebrow("Needs you", color: Palette.redText)
                if tracker.napSummary != nil { NapSummaryCard(tracker: tracker) }
                if !tracker.urgentMessages.isEmpty { UrgentMessagesCard(tracker: tracker) }
                ForEach(tracker.requests) { RequestCard(request: $0, tracker: tracker, draft: $0.draft) }
                ForEach(tracker.waitingAgents) { task in
                    HStack(spacing: 10) {
                        Circle().fill(Palette.red).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.project).font(.system(size: 13, weight: .semibold))
                            Text("is waiting for you in its terminal").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("Open") { tracker.jump(to: task) }
                            .buttonStyle(.borderedProminent).tint(Palette.red).controlSize(.small)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.alertBg))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.alertBorder, lineWidth: 1))
                }
                if tracker.yesterdayNote != nil { YesterdayNoteCard(tracker: tracker) }
                if tracker.endOfDayDue { EndOfDayCard(tracker: tracker, draft: tracker.noteDraft) }
                if let r = tracker.dueReminder { ReminderCard(tracker: tracker, reminder: r) }
                if tracker.waterDue { WaterCard(tracker: tracker) }
                if tracker.breakDue { BreakCard(tracker: tracker) }
            }
        }

        VStack(alignment: .leading, spacing: 2) {
            eyebrow("Running · \(running.count)").padding(.bottom, 4)
            if running.isEmpty {
                Text("No agents working right now.").font(.system(size: 12)).foregroundStyle(Palette.faint).padding(.horizontal, 8)
            }
            ForEach(Array(running.enumerated()), id: \.element.id) { i, task in
                AgentRow(task: task, now: now, highlighted: i % 2 == 1) { tracker.openChat(task.id) }
            }
        }

        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                eyebrow("Done today · \(done.count)").padding(.bottom, 4)
                let shown = tracker.showAllDone ? done : Array(done.prefix(3))
                ForEach(shown) { task in
                    AgentRow(task: task, now: now, highlighted: false) { tracker.openChat(task.id) }
                }
                if done.count > 3 {
                    Button(tracker.showAllDone ? "Show less" : "Show \(done.count - 3) more") { tracker.showAllDone.toggle() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.horizontal, 8)
                }
            }
        }

        if !tracker.backgroundAgents.isEmpty || !tracker.cloudBranches.isEmpty {
            BackgroundCloudSection(tracker: tracker, now: now)
        }

        if !idle.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Button { tracker.showIdle.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tracker.showIdle ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                        eyebrow("Idle in herdr · \(idle.count)")
                    }
                    .foregroundStyle(Palette.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
                if tracker.showIdle {
                    ForEach(idle) { task in
                        AgentRow(task: task, now: now, highlighted: false) { tracker.openChat(task.id) }
                    }
                }
            }
        }
    }
}

// MARK: - Code tab

struct CodeTab: View {
    @ObservedObject var tracker: Tracker
    let now: Date

    var body: some View {
        if tracker.on(.logErrors) && !tracker.logErrors.isEmpty { LogErrorsSection(tracker: tracker) }
        if tracker.on(.pullRequests) { PRSection(tracker: tracker) }
        if tracker.on(.jira) && tracker.jiraConfigured { JiraSection(tracker: tracker) }
        if tracker.on(.prStats) { PRStatsSection(tracker: tracker) }
        if tracker.on(.devStack) && (!tracker.stacks.isEmpty || !tracker.tunnels.isEmpty) {
            StackSection(tracker: tracker)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
        if tracker.on(.deploys) {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(tracker: tracker, key: "deploys", title: "Deploys") {
                Text(tracker.deploys.isEmpty ? "none in 6 h" : "\(tracker.deploys.count) in 6 h")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            if !tracker.closedSections.contains("deploys") {
                ForEach(tracker.deploys) { DeployRow(run: $0, now: now) }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
        if tracker.on(.housekeeping) && tracker.housekeeping.hasNews { HousekeepingSection(tracker: tracker) }
    }
}

// MARK: - Me tab

struct MeTab: View {
    @ObservedObject var tracker: Tracker
    let now: Date

    var body: some View {
        if tracker.panelNeedsYou > 0 && (tracker.waterDue || tracker.breakDue || tracker.dueReminder != nil) {
            if let r = tracker.dueReminder { ReminderCard(tracker: tracker, reminder: r) }
            if tracker.waterDue { WaterCard(tracker: tracker) }
            if tracker.breakDue { BreakCard(tracker: tracker) }
        }
        if tracker.on(.meetings) && tracker.calendarAccess != .unknown { MeetingsCard(tracker: tracker, now: now) }
        if tracker.on(.todos) { TodoCard(tracker: tracker, draft: tracker.todoDraft) }
        if tracker.on(.claudeUsage) { UsageCard(tracker: tracker, now: now) }
        if tracker.on(.timesheet) { TimesheetCard(tracker: tracker, now: now) }
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Today")
            if tracker.on(.breaks) {
                meRow("figure.walk", "Working for \(formatDuration(tracker.workedFor))",
                      "Break nudge after \(Int(tracker.breakMinutes)) min")
            }
            meRow("drop", tracker.waterOn ? "Next water in \(formatDuration(max(0, tracker.nextWaterAt.timeIntervalSince(now))))" : "Water reminders are off",
                  "Every \(Int(tracker.waterMinutes)) min")
            ForEach(tracker.on(.dailyReminders) ? tracker.dailyReminderList : [], id: \.time) { r in
                meRow("clock", "\(r.emoji ?? "⏰") \(r.title)", "Every day at \(r.time)")
            }
            meRow("sunset", "Work hours \(tracker.workHours.start)–\(tracker.workHours.end)",
                  (tracker.offDuty ? "Off duty now: work alerts are quiet · " : "") + tracker.workHours.days.joined(separator: " "))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.raised))

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                eyebrow("Today so far")
                Spacer()
                Button("Copy for standup") { tracker.copySummary() }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(Palette.blue)
            }
            Text(tracker.today.summary()).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.pillText).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.raised))

        if let note = Notes.latest() {
            VStack(alignment: .leading, spacing: 6) {
                eyebrow("Your last note")
                Text(note.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text(DateFormatter.localizedString(from: note.date, dateStyle: .medium, timeStyle: .short))
                    .font(.system(size: 10)).foregroundStyle(Palette.faint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.raised))
        }

        VStack(alignment: .leading, spacing: 8) {
            eyebrow("Quiet time")
            if tracker.napping {
                Button("Wake up") { tracker.wake() }.buttonStyle(.borderedProminent).tint(Palette.blue)
            } else {
                HStack(spacing: 6) {
                    ForEach([(30.0, "30 min"), (60.0, "1 hour"), (120.0, "2 hours")], id: \.0) { m, label in
                        Button("Nap \(label)") { tracker.nap(minutes: m) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Button("I just took a break") { tracker.tookBreak() }.buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(Palette.blue)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.raised))
    }

    private func meRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Palette.muted).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.faint)
            }
        }
    }
}

// MARK: - Status pills (from design B)

struct StatusPills: View {
    @ObservedObject var tracker: Tracker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusHeader
            if !tracker.statusCollapsed {
                if tracker.statusHeight > 0 {
                    ScrollView { flow }.frame(height: min(tracker.statusHeight, max(34, tracker.statusContentHeight)))
                } else {
                    flow
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, tracker.statusCollapsed ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Palette.divider).frame(height: 1) }
    }

    /// "STATUS", a grip to drag it taller or shorter, − / +, and collapse.
    private var statusHeader: some View {
        HStack(spacing: 6) {
            Button { tracker.toggleStatus() } label: {
                HStack(spacing: 4) {
                    Image(systemName: tracker.statusCollapsed ? "chevron.right" : "chevron.down").font(.system(size: 8, weight: .bold))
                    eyebrow("Status")
                }
                .foregroundStyle(Palette.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tracker.statusCollapsed ? "Show the status pills" : "Hide the status pills")
            if tracker.statusCollapsed { collapsedSummary }
            Spacer()
            if !tracker.statusCollapsed {
                Capsule().fill(Palette.faint.opacity(0.5)).frame(width: 34, height: 4)
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { _ in tracker.dragStatusHeight() }
                        .onEnded { _ in tracker.endStatusDrag() })
                    .help("Drag up or down to make the status area taller or shorter")
                Spacer()
                sizeButton("minus", "Shorter") { tracker.stepStatusHeight(-1) }
                    .disabled(tracker.statusHeight > 0 && tracker.statusHeight <= 34)
                sizeButton("plus", "Taller") { tracker.stepStatusHeight(1) }
                    .disabled(tracker.statusHeight == 0)
            }
        }
        .padding(.leading, 4)
    }

    private func sizeButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { action() } }) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.muted)
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(Palette.pill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// While collapsed: just how many lights are red and orange.
    private var collapsedSummary: some View {
        HStack(spacing: 8) {
            let (red, orange) = tracker.statusCounts
            if red > 0 { dot(Palette.red, red) }
            if orange > 0 { dot(Palette.orange, orange) }
            if red == 0 && orange == 0 { dot(Palette.green, nil) }
        }
    }

    private func dot(_ color: Color, _ n: Int?) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            if let n { Text("\(n)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted) }
        }
    }

    private var flow: some View {
            FlowLayout(spacing: 6) {
                if tracker.on(.devStack) && !tracker.stacks.isEmpty {
                    let down = tracker.stacks.reduce(0) { $0 + $1.downCount }
                    pill(down > 0 ? Palette.red : Palette.green, down > 0 ? "Local stack · \(down) down" : "Local stack") { tracker.show(.code) }
                }
                if tracker.on(.pullRequests) {
                    let failing = tracker.prs.filter { $0.checks == .failing }.count
                    pill(failing > 0 ? Palette.red : Palette.green,
                         failing > 0 ? "PRs · \(failing) failing" : "PRs · \(tracker.prs.count) open") { tracker.show(.code) }
                }
                if tracker.on(.jira) && tracker.jiraConfigured {
                    pill(tracker.jiraProblem != nil ? Palette.faint : Palette.blue, "Jira · \(tracker.jiraIssues.count)") { tracker.show(.code) }
                }
                let bgWaiting = tracker.backgroundAgents.filter { $0.state == .waiting }.count
                if bgWaiting > 0 {
                    pill(Palette.red, "Background · \(bgWaiting) waiting") { tracker.show(.agents) }
                }
                if !tracker.sites.isEmpty {
                    let down = tracker.sites.filter { $0.failures >= 2 }.count
                    pill(down > 0 ? Palette.red : Palette.green, down > 0 ? "Sites · \(down) down" : "Sites") { tracker.show(.cloud) }
                }
                if !tracker.ecs.isEmpty {
                    let down = tracker.ecs.filter(\.isUnhealthy).count
                    pill(down > 0 ? Palette.red : Palette.green, down > 0 ? "ECS · \(down) down" : "ECS") { tracker.show(.cloud) }
                }
                if tracker.on(.gcp) && !tracker.gcpProjects.isEmpty {
                    let down = tracker.cloudRun.filter(\.isUnhealthy).count
                    pill(down > 0 ? Palette.red : Palette.green, down > 0 ? "Cloud Run · \(down) down" : "Cloud Run") { tracker.show(.cloud) }
                }
                if tracker.on(.gcp) && Gcp.available && !tracker.gcpProjects.isEmpty {
                    pill(tracker.gcp.isLoggedOut ? Palette.red : tracker.gcp == .unknown ? Palette.faint : Palette.green,
                         tracker.gcp.isLoggedOut ? "GCP · log in" : "GCP") {
                        if tracker.gcp.isLoggedOut { tracker.loginGcp() } else { tracker.checkGcp() }
                    }
                }
                if let u = tracker.usage, let pct = [u.fiveHour?.percent, u.week?.percent].compactMap({ $0 }).max() {
                    pill(UsageCard.color(pct), "Claude · \(Int(pct.rounded()))% used") { tracker.show(.me) }
                }
                if tracker.on(.meetings), let m = tracker.meetings.first(where: { $0.isNow(Date()) || $0.start.timeIntervalSinceNow < 1800 }) {
                    pill(m.isNow(Date()) ? Palette.red : Palette.orange,
                         m.isNow(Date()) ? "In: \(oneLine(m.title, max: 24))" : "\(oneLine(m.title, max: 24)) in \(max(1, Int(m.start.timeIntervalSinceNow / 60))) min") {
                        if m.joinURL != nil { tracker.joinMeeting(m) } else { tracker.show(.me) }
                    }
                }
                let openTodos = tracker.on(.todos) ? tracker.todos.filter { $0.done == nil }.count : 0
                if openTodos > 0 {
                    pill(Palette.blue, "To-do · \(openTodos)") { tracker.show(.me) }
                }
                if tracker.on(.aws) {
                    pill(tracker.aws.isLoggedOut ? Palette.red : tracker.aws == .unknown ? Palette.faint : Palette.green,
                         tracker.aws.isLoggedOut ? "AWS · log in" : "AWS") {
                        if tracker.aws.isLoggedOut { tracker.loginAws() } else { tracker.checkAws() }
                    }
                }
                if tracker.on(.deploys) {
                    let activeDeploys = tracker.deploys.filter(\.isActive).count
                    let failedDeploy = tracker.deploys.contains { !$0.isActive && !["success", "cancelled", "skipped"].contains($0.conclusion) }
                    pill(failedDeploy ? Palette.red : activeDeploys > 0 ? Palette.orange : Palette.green,
                         activeDeploys > 0 ? "Deploys · \(activeDeploys) running" : "Deploys") { tracker.show(.code) }
                }
                let h = tracker.housekeeping
                if tracker.on(.housekeeping) && h.freeGB > 0 {
                    let bigLog = h.bigLogs.first.map { " · \($0.detail) log" } ?? ""
                    pill(h.lowDisk ? Palette.red : h.hasNews ? Palette.orange : Palette.green,
                         h.lowDisk ? String(format: "Disk · %.0f GB free", h.freeGB) : "Disk" + bigLog) { tracker.show(.code) }
                }
            }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { tracker.statusContentHeight = g.size.height }
                    .onChange(of: g.size.height) { _, h in tracker.statusContentHeight = h }
            })
    }

    private func pill(_ color: Color, _ text: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { action() } }) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text).font(.system(size: 12)).foregroundStyle(Palette.pillText).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Palette.pill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Lays children out left to right, wrapping onto new lines like words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Sites and local errors

struct SitesSection: View {
    @ObservedObject var tracker: Tracker
    var body: some View {
        let down = tracker.sites.filter { $0.failures >= 2 }.count
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(tracker: tracker, key: "sites", title: "Sites") {
                Text(tracker.sites.isEmpty ? "checking…" : down > 0 ? "⚠ \(down) down" : "✓ all up")
                    .font(.system(size: 10)).foregroundStyle(down > 0 ? Palette.redText : Palette.muted)
            }
            if !tracker.closedSections.contains("sites") {
                ForEach(tracker.sites) { site in
                    HStack(spacing: 8) {
                        Circle().fill(site.ok ? Palette.green : site.failures >= 2 ? Palette.red : Palette.orange)
                            .frame(width: 7, height: 7)
                        Text(site.name).font(.system(size: 12))
                        if site.prod {
                            Text("prod").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.redText)
                        }
                        Spacer()
                        Text(site.ok ? "\(site.ms) ms" : site.code == 0 ? "no response" : "HTTP \(site.code)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(site.ok ? Palette.faint : Palette.redText)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if let u = URL(string: site.url) { NSWorkspace.shared.open(u) } }
                    .help(site.url)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

struct LogErrorsSection: View {
    @ObservedObject var tracker: Tracker
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(tracker: tracker, key: "logerrors", title: "Errors in local logs") {
                Button("Clear") { tracker.logErrors.removeAll() }.buttonStyle(.plain)
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            if !tracker.closedSections.contains("logerrors") {
                ForEach(tracker.logErrors) { err in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(err.stack) · \(err.service)").font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text(err.at, style: .relative).font(.system(size: 10)).foregroundStyle(Palette.faint)
                        }
                        Text(err.line).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.redText)
                            .lineLimit(3).textSelection(.enabled)
                        HStack(spacing: 12) {
                            Button("Open log") { NSWorkspace.shared.open(URL(fileURLWithPath: err.path)) }
                            Button("Ask an agent to fix") { tracker.askAgentAbout(err) }
                        }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.blue)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.alertBg))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Resizing

/// Drag the top-left corner (both), the left edge (width) or the top edge (height).
struct ResizeHandles: View {
    @ObservedObject var tracker: Tracker

    var body: some View {
        ZStack(alignment: .topLeading) {
            edge(width: true, height: false, cursor: .resizeLeftRight)   // left edge
                .frame(width: 6).frame(maxHeight: .infinity).padding(.top, 18)
            edge(width: false, height: true, cursor: .resizeUpDown)      // top edge
                .frame(height: 6).frame(maxWidth: .infinity).padding(.leading, 18)
            edge(width: true, height: true, cursor: .crosshair)          // corner
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.faint)
                        .rotationEffect(.degrees(90))
                        .offset(x: 2, y: 2)
                )
                .help("Drag to resize the panel")
        }
    }

    private func edge(width: Bool, height: Bool, cursor: NSCursor) -> some View {
        Color.white.opacity(0.001) // invisible but hit-testable
            .contentShape(Rectangle())
            .onHover { inside in inside ? cursor.push() : NSCursor.pop() }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in tracker.resizePanel(width: width, height: height) }
                    .onEnded { _ in tracker.endResize() }
            )
    }
}

// MARK: - Google Cloud Run

struct CloudRunSection: View {
    @ObservedObject var tracker: Tracker
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 4, alignment: .leading)]

    var body: some View {
        let down = tracker.cloudRun.filter(\.isUnhealthy)
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(tracker: tracker, key: "cloudrun", title: "Google Cloud Run") {
                Text(tracker.cloudRun.isEmpty ? "" : down.isEmpty ? "✓ \(tracker.cloudRun.count) ready" : "⚠ \(down.count) not ready")
                    .font(.system(size: 10)).foregroundStyle(down.isEmpty ? Palette.muted : Palette.redText)
            }
            if !tracker.closedSections.contains("cloudrun") {
                if !Gcp.available {
                    Text("Install the Google Cloud CLI (gcloud) to watch Cloud Run.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                } else if tracker.gcp.isLoggedOut {
                    Button("Log in to Google Cloud") { tracker.loginGcp() }.buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(Palette.blue)
                } else if tracker.cloudRun.isEmpty {
                    Text(tracker.gcpProblems.first ?? "Checking…").font(.system(size: 11)).foregroundStyle(Palette.muted)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                        ForEach(tracker.cloudRun) { s in
                            let color = s.isUnhealthy ? Palette.red : s.deploying ? Palette.orange : Palette.green
                            HStack(spacing: 4) {
                                Circle().fill(color).frame(width: 7, height: 7)
                                Text(s.name).font(.system(size: 10)).lineLimit(1)
                                if s.isProduction { Text("prod").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.redText) }
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.1)))
                            .contentShape(Rectangle())
                            .onTapGesture { if let u = s.consoleURL { NSWorkspace.shared.open(u) } }
                            .help("\(s.project) · \(s.region)\n\(s.message.isEmpty ? s.url : s.message)\nClick to open in the Google Cloud console.")
                        }
                    }
                    ForEach(down) { s in
                        Text("\(s.name): \(s.message)").font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.redText).lineLimit(3).textSelection(.enabled)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}
