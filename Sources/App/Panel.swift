// The panel that opens when you click the buddy: design "A · Tabs" with the
// status pills from "B · Inbox". Header (AWS, remote, settings), four number
// tiles, tabs (Agents · Code · Cloud · Me), and status pills at the bottom.
import AppKit
import SwiftUI

enum PanelTab: String, CaseIterable {
    case agents = "Agents", code = "Code", cloud = "Cloud", me = "Me"

    var icon: String {
        switch self {
        case .agents: "sparkles"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .cloud: "cloud.fill"
        case .me: "person.fill"
        }
    }
}

/// A color scheme for the panel (⚙︎ → Theme). "Auto" follows the Mac's light/dark setting.
struct PanelTheme {
    let name: String
    let isDark: Bool
    let bg, border, text, muted, faint, raised, well, segment, pill, pillText: UInt32
    let red, redText, orange, green, blue: UInt32
    let needBg, needLabel, runBg, runNumber, runLabel, neutralBg, neutralLabel: UInt32
    let alertBg, alertBorder, alertText, divider: UInt32
    /// iOS-style shapes: frosted glass, icon squares, inset cards, capsule buttons.
    var isApple = false

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

    /// Apple's iOS system colors (grouped backgrounds, labels, separators, system tints).
    static let appleLight = PanelTheme(
        name: "Apple Light", isDark: false,
        bg: 0xF2F2F7, border: 0xD1D1D6, text: 0x000000, muted: 0x6C6C70, faint: 0xAEAEB2, raised: 0xFFFFFF,
        well: 0xE3E3E8, segment: 0xFFFFFF, pill: 0xFFFFFF, pillText: 0x1C1C1E,
        red: 0xFF3B30, redText: 0xFF3B30, orange: 0xFF9500, green: 0x34C759, blue: 0x007AFF,
        needBg: 0xFFFFFF, needLabel: 0x6C6C70, runBg: 0xFFFFFF, runNumber: 0xFF9500, runLabel: 0x6C6C70,
        neutralBg: 0xFFFFFF, neutralLabel: 0x6C6C70,
        alertBg: 0xFFFFFF, alertBorder: 0xFF3B30, alertText: 0x3A0B08, divider: 0xD8D8DC, isApple: true)

    static let appleDark = PanelTheme(
        name: "Apple Dark", isDark: true,
        bg: 0x1C1C1E, border: 0x38383A, text: 0xFFFFFF, muted: 0x98989F, faint: 0x636366, raised: 0x2C2C2E,
        well: 0x3A3A3C, segment: 0x636366, pill: 0x2C2C2E, pillText: 0xEBEBF5,
        red: 0xFF453A, redText: 0xFF6961, orange: 0xFF9F0A, green: 0x30D158, blue: 0x0A84FF,
        needBg: 0x2C2C2E, needLabel: 0x98989F, runBg: 0x2C2C2E, runNumber: 0xFF9F0A, runLabel: 0x98989F,
        neutralBg: 0x2C2C2E, neutralLabel: 0x98989F,
        alertBg: 0x2C2C2E, alertBorder: 0xFF453A, alertText: 0xFFD6D3, divider: 0x38383A, isApple: true)

    static let all = [midnight, daylight, ocean, sunset, appleLight, appleDark]

    private static var macIsDark: Bool { NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    /// The chosen theme. "Auto" picks Midnight or Daylight, and "Apple" Apple Light or Dark,
    /// from the Mac's appearance.
    nonisolated(unsafe) static var choice = UserDefaults.standard.string(forKey: "panelTheme") ?? "Auto"
    static var current: PanelTheme {
        if choice == "Apple" { return macIsDark ? appleDark : appleLight }
        if let t = all.first(where: { $0.name == choice }) { return t }
        return macIsDark ? midnight : daylight
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
    static var isApple: Bool { t.isApple }
}

/// Frosted glass that blurs the desktop behind the panel (the Apple theme), like
/// Control Center. In the README images (drawn offscreen) it falls back to a solid fill.
struct FrostedGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Apple's Liquid Glass (macOS 26, as in iOS 26) in `shape`, optionally tinted and
    /// reacting to the pointer. Older macOS, and the README images, get `fallback` instead.
    /// (Built with an older Xcode, without the macOS 26 SDK, it's always the fallback.)
    @ViewBuilder
    func liquidGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, fallback: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !DocsRenderer.active {
            let glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            self.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            self.background(shape.fill(fallback ?? tint ?? Palette.raised))
        }
        #else
        self.background(shape.fill(fallback ?? tint ?? Palette.raised))
        #endif
    }

    /// Liquid Glass is there (macOS 26, built with Xcode 26 or later).
    static var hasLiquidGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }
}

/// The panel's background: the theme's color, or Liquid Glass for the Apple theme.
struct PanelBackground: View {
    var radius: CGFloat = 20
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Palette.isApple ? radius + 8 : radius, style: .continuous)
        if Palette.isApple {
            if Self.hasLiquidGlass && !DocsRenderer.active {
                // Glass, with a veil of the theme color so text stays readable over a busy desktop.
                Color.clear.liquidGlass(shape).overlay(shape.fill(Palette.bg.opacity(Palette.scheme == .dark ? 0.62 : 0.55)))
            } else if !DocsRenderer.active {
                FrostedGlass().clipShape(shape).overlay(shape.fill(Palette.bg.opacity(0.55)))
            } else {
                shape.fill(Palette.bg)
            }
        } else {
            shape.fill(Palette.bg)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// A small section label ("RUNNING · 2"), with the section's icon when it has one.
func eyebrow(_ text: String, color: Color = Palette.muted) -> some View {
    Group {
        if Palette.isApple {
            // iOS Settings style: a white glyph in a colored rounded square, then the title.
            HStack(spacing: 7) {
                if let icon = sectionIcon(text) {
                    Image(systemName: icon).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(sectionColor(text)))
                }
                Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(color == Palette.muted ? Palette.text : color)
            }
        } else {
            HStack(spacing: 5) {
                if let icon = sectionIcon(text) {
                    Image(systemName: icon).font(.system(size: 9.5, weight: .semibold))
                }
                Text(text.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(color)
        }
    }
}

/// Each section's square color in the Apple theme, like the icons in iOS Settings.
func sectionColor(_ title: String) -> Color {
    let t = title.lowercased()
    let colors: [(String, UInt32)] = [
        ("needs you", 0xFF3B30), ("running", 0xFF9500), ("done today", 0x34C759), ("idle", 0x8E8E93),
        ("background", 0x5856D6), ("pull requests", 0x5856D6), ("pr stats", 0xAF52DE), ("jira", 0x007AFF),
        ("local stack", 0x34C759), ("deploys", 0x007AFF), ("errors", 0xFF3B30), ("housekeeping", 0x8E8E93),
        ("sites", 0x32ADE6), ("cloud run", 0x5AC8FA), ("cloud", 0x5AC8FA), ("meetings", 0xFF3B30), ("to-do", 0xFF9500),
        ("claude plan", 0xD97757), ("timesheet", 0x5856D6), ("today so far", 0x34C759), ("today", 0xFFCC00),
        ("your last note", 0xFFCC00), ("quiet time", 0x5856D6), ("status", 0x8E8E93),
    ]
    return Color(hex: colors.first { t.hasPrefix($0.0) }?.1 ?? 0x8E8E93)
}

/// Each section's icon, by the start of its title.
func sectionIcon(_ title: String) -> String? {
    let t = title.lowercased()
    let icons: [(String, String)] = [
        ("needs you", "exclamationmark.bubble.fill"), ("running", "bolt.fill"), ("done today", "checkmark.circle.fill"),
        ("idle in herdr", "moon.zzz.fill"), ("background", "square.stack.3d.up.fill"), ("pull requests", "arrow.triangle.pull"),
        ("pr stats", "chart.bar.fill"), ("jira", "ticket.fill"), ("local stack", "server.rack"), ("deploys", "paperplane.fill"),
        ("errors", "ladybug.fill"), ("housekeeping", "internaldrive.fill"), ("sites", "globe"), ("cloud run", "cloud.fill"),
        ("cloud", "cloud.fill"), ("meetings", "calendar"), ("to-do", "checklist"), ("claude plan", "gauge.with.dots.needle.50percent"),
        ("timesheet", "clock.fill"), ("today so far", "list.bullet.rectangle"), ("today", "sun.max.fill"),
        ("your last note", "note.text"), ("quiet time", "moon.fill"), ("status", "circle.grid.2x2.fill"),
    ]
    return icons.first { t.hasPrefix($0.0) }?.1
}

extension View {
    /// The panel's one card style: a raised surface, a hairline border, soft corners.
    func panelCard(padding: CGFloat = 12) -> some View {
        let r: CGFloat = Palette.isApple ? 14 : 12
        return self.padding(Palette.isApple ? padding + 2 : padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Palette.isApple ? Palette.raised.opacity(Palette.scheme == .dark ? 0.85 : 0.92) : Palette.raised))
            // iOS cards have no outline; the classic themes do.
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
                .stroke(Palette.isApple ? .clear : Palette.border.opacity(0.75), lineWidth: 1))
    }
}

/// Panel buttons. The system's prominent style turns grey whenever its window isn't the
/// active one, and the buddy's panel never takes focus, so it draws its own.
struct ActionButtonStyle: ButtonStyle {
    var color: Color?          // filled in this color; nil = a quiet grey button
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        if Palette.isApple { appleBody(configuration) } else { classicBody(configuration) }
    }

    /// iOS 26: a Liquid Glass capsule, tinted for the main action.
    private func appleBody(_ configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 11 : 12.5, weight: .semibold))
            .foregroundStyle(color == nil ? Palette.text : .white)
            .padding(.horizontal, small ? 11 : 15)
            .frame(height: small ? 24 : 30)
            .liquidGlass(Capsule(), tint: color, interactive: true, fallback: color ?? Palette.well)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func classicBody(_ configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 11 : 12, weight: .semibold))
            .foregroundStyle(color == nil ? Palette.text : .white)
            .padding(.horizontal, small ? 10 : 13)
            .frame(height: small ? 24 : 28)
            .background(
                RoundedRectangle(cornerRadius: Palette.isApple ? 100 : (small ? 7 : 8), style: .continuous)
                    .fill(color ?? (Palette.isApple ? Palette.well : Palette.pill))
                    .overlay(RoundedRectangle(cornerRadius: Palette.isApple ? 100 : (small ? 7 : 8), style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(color == nil || Palette.isApple ? 0.04 : 0.18), .clear], startPoint: .top, endPoint: .bottom)))
            )
            .overlay(RoundedRectangle(cornerRadius: Palette.isApple ? 100 : (small ? 7 : 8), style: .continuous)
                .stroke(Palette.isApple ? .clear : (color == nil ? Palette.border : .black.opacity(0.15)), lineWidth: 1))
            .shadow(color: (color ?? .black).opacity(color == nil || Palette.isApple ? 0 : 0.35), radius: 4, y: 2)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The tab bar's track: a floating glass capsule (iOS 26 tab bar) or the classic well.
struct TabTrack: ViewModifier {
    func body(content: Content) -> some View {
        if Palette.isApple { content.liquidGlass(Capsule(), fallback: Palette.well) }
        else { content.background(RoundedRectangle(cornerRadius: 10).fill(Palette.well)) }
    }
}

/// Liquid Glass capsules for the Apple theme; nothing for the others.
struct AppleGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if Palette.isApple { content.liquidGlass(Capsule(), interactive: true, fallback: Palette.pill) } else { content }
    }
}

/// A round icon button for the panel header.
func headerButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Group {
            if Palette.isApple {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.text)
                    .frame(width: 26, height: 26)
                    .liquidGlass(Circle(), interactive: true, fallback: Palette.pill)
            } else {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Palette.pill))
            }
        }
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
}

struct TaskListView: View {
    @ObservedObject var tracker: Tracker
    private var panelRadius: CGFloat { Palette.isApple ? 26 : 20 }

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
                        Group {
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
        .background(
            PanelBackground()
                // A soft light from the top, so the panel reads as a surface rather than a flat box.
                .overlay(RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(Palette.scheme == .dark ? 0.05 : (Palette.isApple ? 0.2 : 0.5)), .clear],
                                         startPoint: .top, endPoint: .center)))
        )
        .overlay(RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Color.white.opacity(Palette.scheme == .dark ? 0.12 : 0.6), Palette.border.opacity(Palette.isApple ? 0.5 : 1)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: Palette.isApple ? 0.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .overlay(alignment: .topLeading) { ResizeHandles(tracker: tracker) }
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .environment(\.colorScheme, Palette.scheme)
        .animation(.easeInOut(duration: 0.25), value: tracker.panelTheme)
    }

    // MARK: Header

    /// The buddy's mood light, the name, a one-line summary, then the controls.
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tracker.mood.color.opacity(0.25)).frame(width: 22, height: 22)
                Circle().fill(tracker.mood.color).frame(width: 9, height: 9)
                    .shadow(color: tracker.mood.color.opacity(0.8), radius: 4)
            }
            // Two lines: the name and the controls, then the summary and the cloud logins.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Agent Buddy").font(Palette.isApple ? .system(size: 20, weight: .bold) : .system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1).fixedSize()
                    Spacer(minLength: 4)
                    headerControls
                }
                HStack(spacing: 6) {
                    Text(tracker.headerSummary).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    Spacer(minLength: 4)
                    // Cloud logins at a glance: green = logged in, red = log in (click), grey = unknown.
                    if tracker.on(.aws) { AwsPill(tracker: tracker).fixedSize() }
                    if tracker.on(.gcp) && Gcp.available { GcpPill(tracker: tracker).fixedSize() }
                }
            }
        }
    }

    private var headerControls: some View {
        HStack(spacing: 6) {
            Button { tracker.autoRemoteOn = false; tracker.remoteMode.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 10, weight: .semibold))
                    Text("Remote").font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 9).frame(height: 26)
                .background(Capsule().fill(tracker.remoteMode ? Palette.blue.opacity(0.22) : Palette.pill))
                .overlay(Capsule().stroke(tracker.remoteMode ? Palette.blue.opacity(0.6) : .clear, lineWidth: 1))
                .foregroundStyle(tracker.remoteMode ? Palette.blue : Palette.muted)
                .fixedSize()
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(tracker.remoteMode ? "Remote is on: agents wait for your answers here" : "Remote is off: answer agents in the terminal")
            headerButton(tracker.panelCompact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                         help: tracker.panelCompact ? "Show everything" : "Minimize: just the numbers and status") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tracker.panelCompact.toggle() }
            }
            settingsMenu
            headerButton("xmark", help: "Close (or click the buddy)") { tracker.closePanel() }
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
                ForEach(PanelTheme.all.filter { !$0.isApple }, id: \.name) { Text($0.name).tag($0.name) }
                Text("Apple (iOS style)").tag("Apple")
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
            Image(systemName: "gearshape.fill").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 26, height: 26)
        .background(Circle().fill(Palette.pill))
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
            tile(tracker.panelNeedsYou, "need you", icon: "exclamationmark.bubble.fill",
                 color: tracker.panelNeedsYou > 0 ? Palette.red : nil) { tracker.show(.agents) }
            tile(tracker.runningAgents.count, "running", icon: "bolt.fill",
                 color: tracker.runningAgents.isEmpty ? nil : Palette.orange) { tracker.show(.agents) }
            tile(failingPRs, "PRs failing", icon: "arrow.triangle.pull",
                 color: failingPRs > 0 ? Palette.red : nil) { tracker.show(.code) }
            tile(ecsDown, "cloud down", icon: "cloud.bolt.fill",
                 color: ecsDown > 0 ? Palette.red : nil) { tracker.show(.cloud) }
        }
    }

    /// A number tile: lit in its color when there's something to see, quiet when it's zero.
    private func tile(_ n: Int, _ label: String, icon: String, color: Color?, action: @escaping () -> Void) -> some View {
        Group {
            if Palette.isApple { appleTile(n, label, icon: icon, color: color, action: action) }
            else { classicTile(n, label, icon: icon, color: color, action: action) }
        }
    }

    /// Control Center style: the icon in a filled circle (grey when there's nothing), a big number, the label.
    private func appleTile(_ n: Int, _ label: String, icon: String, color: Color?, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { action() } }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(color == nil ? Palette.muted : .white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(color ?? Palette.well))
                    Text("\(n)").font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                }
                Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.muted)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true,
                         fallback: Palette.raised.opacity(Palette.scheme == .dark ? 0.85 : 0.92))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func classicTile(_ n: Int, _ label: String, icon: String, color: Color?, action: @escaping () -> Void) -> some View {
        let tint = color ?? Palette.muted
        return Button(action: { withAnimation(.easeInOut(duration: 0.15)) { action() } }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text("\(n)").font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(color ?? Palette.text.opacity(0.55))
                        .contentTransition(.numericText())
                    Spacer(minLength: 2)
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint.opacity(color == nil ? 0.6 : 1))
                }
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.map { $0.opacity(0.13) } ?? Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.map { $0.opacity(0.35) } ?? Palette.border.opacity(0.75), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                let on = tracker.panelTab == tab
                let badge = tracker.badge(for: tab)
                Button { withAnimation(.easeInOut(duration: 0.18)) { tracker.panelTab = tab } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 10.5, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 12, weight: on ? .semibold : .medium))
                        if badge > 0 {
                            Text("\(badge)").font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16)
                                .background(Capsule().fill(Palette.red))
                        }
                    }
                    .foregroundStyle(on ? Palette.text : Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Palette.isApple ? 100 : 8, style: .continuous)
                        .fill(on ? (Palette.isApple ? Palette.text.opacity(Palette.scheme == .dark ? 0.16 : 0.09) : Palette.segment) : .clear)
                        .shadow(color: .black.opacity(on && !Palette.isApple ? 0.18 : 0), radius: 2, y: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .modifier(TabTrack())
    }
}

// MARK: - Agents tab

/// A project's initials in a rounded square, tinted with its state's color, with a status dot.
struct Avatar: View {
    let name: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        Group {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
            else { Text(initials).font(.system(size: 11, weight: .bold, design: .rounded)) }
        }
        .foregroundStyle(color)
        .frame(width: 30, height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.15)))
        .overlay(alignment: .bottomTrailing) {
            Circle().fill(color).frame(width: 9, height: 9)
                .overlay(Circle().stroke(Palette.bg, lineWidth: 2))
                .offset(x: 2, y: 2)
        }
    }

    /// "payments-api" → "PA", "shop" → "SH".
    private var initials: String {
        let clean = name.replacingOccurrences(of: "codex · ", with: "")
        let words = clean.split(whereSeparator: { "-_ .·".contains($0) })
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first).map(String.init) : [String(clean.prefix(2))]
        return letters.joined().uppercased()
    }
}

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
            Avatar(name: task.project, color: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(task.project).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if task.kind == "codex" {
                        Text("Codex").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.muted)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Palette.pill))
                    }
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
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(highlighted ? Palette.raised : .clear))
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
                            .buttonStyle(ActionButtonStyle(color: Palette.red, small: true))
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
                .panelCard(padding: 10)
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
        .panelCard(padding: 10)
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
        .panelCard()

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
        .panelCard()

        if let note = Notes.latest() {
            VStack(alignment: .leading, spacing: 6) {
                eyebrow("Your last note")
                Text(note.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text(DateFormatter.localizedString(from: note.date, dateStyle: .medium, timeStyle: .short))
                    .font(.system(size: 10)).foregroundStyle(Palette.faint)
            }
            .panelCard()
        }

        VStack(alignment: .leading, spacing: 8) {
            eyebrow("Quiet time")
            if tracker.napping {
                Button("Wake up") { tracker.wake() }.buttonStyle(ActionButtonStyle(color: Palette.blue))
            } else {
                HStack(spacing: 6) {
                    ForEach([(30.0, "30 min"), (60.0, "1 hour"), (120.0, "2 hours")], id: \.0) { m, label in
                        Button("Nap \(label)") { tracker.nap(minutes: m) }.buttonStyle(ActionButtonStyle(small: true))
                    }
                }
                Button("I just took a break") { tracker.tookBreak() }.buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(Palette.blue)
            }
        }
        .panelCard()
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
                let openTodos = tracker.on(.todos) ? tracker.todos.filter { $0.done == nil } : []
                if !openTodos.isEmpty {
                    let late = openTodos.filter { $0.isLate(Date()) }.count
                    let next = openTodos.compactMap(\.due).filter { $0 > Date() }.min()
                    pill(late > 0 ? Palette.red : Palette.blue,
                         late > 0 ? "To-do · \(late) late" : next.map { "To-do · next \(Todo.timeText($0))" } ?? "To-do · \(openTodos.count)") {
                        tracker.show(.me)
                    }
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
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.7), radius: 2)
                Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.pillText).lineLimit(1)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Palette.isApple ? nil : Capsule().fill(Palette.pill))
            .overlay(Palette.isApple ? nil : Capsule().stroke(Palette.border.opacity(0.6), lineWidth: 1))
            .modifier(AppleGlassCapsule())
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
        .panelCard(padding: 10)
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
        .panelCard(padding: 10)
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
        .panelCard(padding: 10)
    }
}
