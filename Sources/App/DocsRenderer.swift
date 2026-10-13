// `AgentBuddy --render-docs <folder>`: renders the README's images from the real
// views and 3D characters, filled with made-up sample data (never your real
// agents, repos, notes or settings), then exits.
import AppKit
import ImageIO
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum DocsRenderer {
    /// True while drawing the README images.
    nonisolated(unsafe) static var active = false

    static func run(outDir: String) -> Never {
        active = true
        let out = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // Sample settings and notes only: point the app's files at a scratch folder.
        let scratch = out.appendingPathComponent(".render-tmp")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        BuddyConfig.url = scratch.appendingPathComponent("config.json")
        Notes.url = scratch.appendingPathComponent("notes.json")
        Todos.url = scratch.appendingPathComponent("todos.json")
        ClaudeUsage.url = scratch.appendingPathComponent("usage.json")
        DayLog.dir = scratch.appendingPathComponent("days")
        try? sampleConfig.data(using: .utf8)?.write(to: BuddyConfig.url)
        Notes.save("Ship the checkout dark mode, then review design-system #31.")

        PanelTheme.choice = "Midnight" // the README's main images use the default dark theme
        let tracker = sampleTracker()
        var written: [String] = []
        func save(_ image: NSImage?, _ name: String) {
            guard let image, let png = pngData(image) else { print("✗ \(name)"); return }
            try? png.write(to: out.appendingPathComponent(name))
            written.append(name)
        }

        // 1. Characters in every mood
        let moods: [(Mood, String)] = [(.idle, "Idle"), (.working, "Working"), (.waiting, "Needs you"),
                                       (.celebrating, "Done!"), (.stretching, "Break time")]
        let grid = VStack(alignment: .leading, spacing: 18) {
            ForEach(BuddyCharacterKind.allCases) { kind in
                HStack(spacing: 10) {
                    Text(kind.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.text).frame(width: 84, alignment: .leading)
                    ForEach(moods, id: \.1) { mood, label in
                        tile(kind, mood: mood, activity: nil, label: label)
                    }
                }
            }
        }
        save(snapshot(card(grid)), "characters.png")

        // 2. Acting out your day
        let day = HStack(spacing: 14) {
            tile(.nori, mood: .idle, activity: .eat, label: "Lunch: eating")
            tile(.nori, mood: .idle, activity: .drink, label: "Water: drinking")
            tile(.nori, mood: .idle, activity: .sleep, label: "Night: sleeping")
            tile(.nori, mood: .idle, activity: nil, label: "Production!", prod: true)
        }
        save(snapshot(card(day)), "day.png")

        // Festival costumes
        let festivals: [(BuddyCharacterKind, Costume, String)] = [
            (.nori, .diya, "Diwali"), (.bolt, .santaHat, "Christmas"), (.quackers, .partyHat, "New Year"),
            (.sage, .witchHat, "Halloween"), (.nova, .flag, "Independence Day"), (.nori, .holi, "Holi"),
        ]
        let dressed = HStack(spacing: 10) {
            ForEach(festivals, id: \.2) { kind, costume, label in
                tile(kind, mood: .idle, activity: nil, label: label, costume: costume)
            }
        }
        save(snapshot(card(dressed)), "festivals.png")

        // 3. The panel: each tab, and minimized
        tracker.panelWidth = 440
        for tab in PanelTab.allCases {
            tracker.panelTab = tab
            tracker.panelHeight = tab == .me ? 1010 : tab == .code ? 640 : 430
            save(snapshot(TaskListView(tracker: tracker).padding(14)), "panel-\(tab.rawValue.lowercased()).png")
        }
        tracker.panelHeight = 430
        tracker.panelCompact = true
        save(snapshot(TaskListView(tracker: tracker).padding(14)), "panel-minimized.png")
        tracker.panelCompact = false

        // Themes, side by side
        tracker.panelTab = .agents
        tracker.panelHeight = 300
        var shots: [(String, NSImage)] = []
        for theme in PanelTheme.all {
            PanelTheme.choice = theme.name
            if let img = snapshot(TaskListView(tracker: tracker).padding(10)) { shots.append((theme.name, img)) }
        }
        PanelTheme.choice = "Midnight"
        let row = HStack(alignment: .top, spacing: 16) {
            ForEach(shots, id: \.0) { name, img in
                VStack(spacing: 8) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 340)
                    Text(name).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color(hex: 0xC9CDD8))
                }
            }
        }
        save(snapshot(card(row)), "themes.png")
        tracker.panelHeight = 430

        // 4. Bubbles over the buddy
        save(snapshot(bubbleScene(text: "✅ payments-api: Fixed the flaky refund test; all 214 tests pass.",
                                  mood: .celebrating, t: 0.43)), "bubble.png")

        // 5. Animated demo
        if let gif = demoGIF() {
            try? gif.write(to: out.appendingPathComponent("demo.gif"))
            written.append("demo.gif")
        }

        try? FileManager.default.removeItem(at: scratch)
        print("Rendered: " + written.joined(separator: ", "))
        exit(0)
    }

    // MARK: Sample data (made up)

    static let sampleConfig = """
    {"repos": ["acme/shop-web"], "deployWorkflowPattern": "deploy", "pollSeconds": 45,
     "workHours": {"start": "09:30", "end": "19:00", "days": ["Mon", "Tue", "Wed", "Thu", "Fri"]},
     "gcpProjects": [{"project": "acme-analytics", "region": "us-central1"}],
     "dailyReminders": [
       {"time": "13:30", "title": "Lunch break", "message": "Step away and have lunch.", "emoji": "🍱", "activity": "eat"},
       {"time": "23:00", "title": "Time to sleep", "message": "Wrap up and get some sleep.", "emoji": "😴", "activity": "sleep"}]}
    """

    static func sampleTracker() -> Tracker {
        let t = Tracker()
        let now = Date()
        func task(_ id: String, _ project: String, _ prompt: String, _ state: TaskState, started: Double,
                  finished: Double? = nil, summary: String? = nil) -> AgentTask {
            var a = AgentTask(id: id, project: project, prompt: prompt, state: state,
                              started: now.addingTimeInterval(-started),
                              finished: finished.map { now.addingTimeInterval(-$0) })
            a.summary = summary
            return a
        }
        t.tasks = [
            task("s1", "shop-web", "Add dark mode to checkout", .working, started: 260),
            task("s2", "mobile-app", "Fix the push notification crash on Android", .working, started: 740),
            task("s3", "payments-api", "Run the staging migration", .waiting, started: 380),
            task("s4", "payments-api", "Fix the flaky refund test", .done, started: 1500, finished: 360,
                 summary: "Fixed the flaky refund test; all 214 tests pass."),
            task("s5", "docs-site", "Update the API reference", .done, started: 4000, finished: 2400,
                 summary: "Updated the API reference for v2 and fixed 12 broken links."),
        ]
        t.requests = [PendingRequest(id: "r1", sessionId: "s3", project: "payments-api",
                                     kind: .permission(tool: "Bash", summary: "npm run migrate -- --env staging\n— Apply the 3 pending migrations"))]
        t.prs = [
            PullRequest(repo: "acme/payments-api", number: 219, title: "Retry webhooks with backoff",
                        url: "https://github.com", isDraft: false, review: "", mergeable: "MERGEABLE", checks: .failing,
                        headRef: "feat/webhook-retry", ciError: "PR Checks: test_refund_partial: expected 200, got 500",
                        agentId: "s4"),
            PullRequest(repo: "acme/shop-web", number: 482, title: "Dark mode for checkout", url: "https://github.com",
                        isDraft: false, review: "APPROVED", mergeable: "MERGEABLE", checks: .passing),
            PullRequest(repo: "acme/mobile-app", number: 77, title: "Android push crash", url: "https://github.com",
                        isDraft: true, review: "", mergeable: "MERGEABLE", checks: .pending),
        ]
        t.reviewPRs = [PullRequest(repo: "acme/design-system", number: 31, title: "Button tokens", url: "https://github.com",
                                   isDraft: false, review: "", mergeable: "", checks: .none)]
        t.deploys = [
            DeployRun(id: 1, repo: "acme/shop-web", workflow: "Deploy production", branch: "main", status: "in_progress",
                      conclusion: "", created: now.addingTimeInterval(-90), updated: now, url: "https://github.com"),
            DeployRun(id: 2, repo: "acme/payments-api", workflow: "Deploy staging", branch: "main", status: "completed",
                      conclusion: "success", created: now.addingTimeInterval(-1500), updated: now.addingTimeInterval(-1200),
                      url: "https://github.com"),
        ]
        t.stacks = [DevStack(path: "/tmp/shop-web", name: "shop-web", slot: "1", env: "local", services: [
            StackService(name: "frontend", port: 5173, status: .up, portOwner: nil, logPath: ""),
            StackService(name: "backend", port: 8000, status: .up, portOwner: nil, logPath: ""),
            StackService(name: "worker", port: nil, status: .down, portOwner: nil, logPath: "/tmp/worker.log",
                         error: "ModuleNotFoundError: No module named 'stripe'"),
            StackService(name: "redis", port: 6379, status: .up, portOwner: nil, logPath: ""),
            StackService(name: "postgres", port: 5432, status: .up, portOwner: nil, logPath: ""),
        ])]
        t.ecs = [
            EcsService(cluster: "shop-staging", name: "shop-staging-api", desired: 2, running: 2, pending: 0, rollout: "COMPLETED", lastEvent: ""),
            EcsService(cluster: "shop-staging", name: "shop-staging-worker", desired: 1, running: 1, pending: 0, rollout: "COMPLETED", lastEvent: ""),
            EcsService(cluster: "shop-prod", name: "shop-prod-api", desired: 3, running: 3, pending: 0, rollout: "COMPLETED", lastEvent: ""),
            EcsService(cluster: "shop-prod", name: "shop-prod-worker", desired: 2, running: 1, pending: 0, rollout: "COMPLETED",
                       lastEvent: "", stopReason: "Essential container in task exited (OutOfMemory)"),
        ]
        t.cloudRun = [
            CloudRunService(project: "acme-analytics", region: "us-central1", name: "ingest", ready: "True", message: "", url: "", deploying: false),
            CloudRunService(project: "acme-analytics", region: "us-central1", name: "reports", ready: "Unknown", message: "", url: "", deploying: true),
        ]
        t.sites = [
            SiteStatus(name: "staging", url: "https://staging.example.com", prod: false, ok: true, code: 200, ms: 212),
            SiteStatus(name: "production", url: "https://example.com", prod: true, ok: true, code: 200, ms: 96),
            SiteStatus(name: "docs", url: "https://docs.example.com", prod: false, ok: false, code: 503, ms: 140, failures: 2),
        ]
        t.aws = .active("you@example.com")
        t.gcp = .active("you@example.com")
        t.housekeeping = Housekeeping(freeGB: 412, totalGB: 994,
                                      bigLogs: [.init(path: NSHomeDirectory() + "/Developer/shop-web/.dev-logs/backend.log", detail: "2.1 GB")])
        var day = DayLog(day: DayLog.key(now))
        day.activeSeconds = 5.5 * 3600
        day.agentsDone = [.init(project: "payments-api", text: "Fixed the flaky refund test; all 214 tests pass.", at: now),
                          .init(project: "docs-site", text: "Updated the API reference for v2.", at: now)]
        day.prsMerged = [.init(project: "shop-web", text: "#479 Faster product search", at: now)]
        day.deploys = [.init(project: "payments-api", text: "Deploy staging (main) · success", at: now)]
        day.agentSeconds = ["shop-web": 7400, "payments-api": 5200, "mobile-app": 2600]
        day.focusSeconds = ["shop-web": 2.5 * 3600, "payments-api": 1.25 * 3600, "Meetings": 3600, "Other": 0.75 * 3600]
        t.today = day
        t.todos = [Todo(text: "Review design-system #31"),
                   Todo(text: "Write the runbook for webhook retries"),
                   Todo(text: "Rotate the staging API keys", done: now)]
        t.usage = ClaudeUsage(fiveHour: .init(percent: 42, resets: now.addingTimeInterval(2 * 3600 + 900)),
                              week: .init(percent: 81, resets: now.addingTimeInterval(3 * 86_400)), at: now)
        t.calendarAccess = .granted
        t.meetings = [Meeting(id: "m1", title: "Design review", start: now.addingTimeInterval(12 * 60),
                              end: now.addingTimeInterval(42 * 60), calendar: "Work", joinURL: URL(string: "https://meet.google.com/")),
                      Meeting(id: "m2", title: "Sprint planning", start: now.addingTimeInterval(95 * 60),
                              end: now.addingTimeInterval(155 * 60), calendar: "Work", joinURL: nil)]
        t.prStats = PRStats(me: "alex", merged: 6, opened: 7, reviewed: 9, mergeHours: 19,
                            board: [.init(login: "maya", merged: 9), .init(login: "alex", merged: 6), .init(login: "sam", merged: 5),
                                    .init(login: "lee", merged: 3), .init(login: "ari", merged: 2)], at: now)
        t.workStreakStart = now.addingTimeInterval(-(72 * 60))
        t.mood = .waiting
        return t
    }

    // MARK: Pieces

    /// The 3D character (real scene, offscreen) with its 2D overlays, at a given moment.
    static func character(_ kind: BuddyCharacterKind, mood: Mood, activity: BuddyActivity?, t: Double, prod: Bool = false,
                          costume: Costume? = nil) -> some View {
        let image = render3D(kind, mood: mood, activity: activity, t: t, costume: costume)
        let buddy = BuddyCharacter(character: kind, mood: mood, activity: activity, prod: prod, count: 0, alert: false, remote: false)
        return ZStack {
            Image(nsImage: image).resizable().frame(width: 130, height: 150).offset(y: 4)
            buddy.overlays(t: t)
        }
        .frame(width: 130, height: 150)
    }

    private static var scenes: [String: Buddy3DScene] = [:]
    private static let device = MTLCreateSystemDefaultDevice()

    static func render3D(_ kind: BuddyCharacterKind, mood: Mood, activity: BuddyActivity?, t: Double, costume: Costume? = nil) -> NSImage {
        let key = "\(kind.rawValue)"
        let scene = scenes[key] ?? Buddy3DScene(character: kind)
        scenes[key] = scene
        scene.scene.background.contents = NSColor.clear
        scene.set(mood: mood, activity: activity)
        scene.set(costume: costume)
        scene.snapColor()
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene.scene
        renderer.pointOfView = scene.cameraNode
        scene.renderer(renderer, updateAtTime: t)
        return renderer.snapshot(atTime: t, with: CGSize(width: 390, height: 450), antialiasingMode: .multisampling4X)
    }

    static func tile(_ kind: BuddyCharacterKind, mood: Mood, activity: BuddyActivity?, label: String, prod: Bool = false,
                     costume: Costume? = nil) -> some View {
        let t: Double = switch (mood, activity) {
        case (.celebrating, _): 0.43
        case (.working, _): 1.15
        case (.waiting, _): 1.2
        case (.stretching, _): 1.3
        default: activity == nil ? 1.9 : 2.2
        }
        return VStack(spacing: 6) {
            character(kind, mood: mood, activity: activity, t: t, prod: prod, costume: costume)
            Text(label).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 6)
        .frame(width: 138)
    }

    static func card<V: View>(_ content: V) -> some View {
        content
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: 0x1A1C22)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.border, lineWidth: 1))
            .padding(10)
    }

    static func bubbleScene(text: String, mood: Mood, t: Double) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            SpeechBubble(text: text, color: mood.color)
            character(.nori, mood: mood, activity: nil, t: t)
        }
        .padding(16)
        .frame(width: 330, height: 280, alignment: .bottomTrailing)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x23262E)))
        .environment(\.colorScheme, .dark)
    }

    // MARK: Demo GIF

    static func demoGIF() -> Data? {
        let steps: [(Mood, String, Double)] = [
            (.idle, "Hi! I'm watching your agents 👀", 1.6),
            (.working, "On it! shop-web started 🛠️", 2.0),
            (.waiting, "🙋 payments-api wants to run: npm run migrate", 2.2),
            (.celebrating, "✅ payments-api: Fixed the flaky refund test; all 214 tests pass.", 2.4),
        ]
        let fps = 12.0
        var frames: [CGImage] = []
        var t = 0.0
        for (mood, text, seconds) in steps {
            for _ in 0..<Int(seconds * fps) {
                t += 1 / fps
                if let img = snapshot(bubbleScene(text: text, mood: mood, t: t), scale: 1)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil) { frames.append(img) }
            }
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for f in frames { CGImageDestinationAddImage(dest, f, frameProps) }
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: Rendering a SwiftUI view to an image

    static func snapshot<V: View>(_ view: V, scale: CGFloat = 2) -> NSImage? {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return nil }
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15)) // let SwiftUI lay out and draw
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first
                ?? image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
