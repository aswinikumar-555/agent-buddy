// The 3D desktop characters (SceneKit): Nori the cat and Bolt the chrome robot.
// Same models, materials, lighting and mood poses as the "Buddy Lineup" page's
// three.js versions.
import AppKit
import SceneKit
import SwiftUI

/// Something the buddy acts out, on top of its mood.
enum BuddyActivity: String {
    case eat, drink, sleep
}

enum BuddyCharacterKind: String, CaseIterable, Identifiable {
    case nori, bolt, quackers, sage, nova
    var id: String { rawValue }
    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var title: String {
        switch self {
        case .nori: "Nori (cat)"
        case .bolt: "Bolt (robot)"
        case .quackers: "Quackers (rubber duck)"
        case .sage: "Sage (owl)"
        case .nova: "Nova (astronaut)"
        }
    }
}

/// Builds one character's scene and animates it every frame from the current mood.
final class Buddy3DScene: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let lock = NSLock()
    private var mood: Mood = .idle
    private var activity: BuddyActivity?
    private var target: (CGFloat, CGFloat, CGFloat) = (0.36, 0.55, 1.0)
    private var current: (CGFloat, CGFloat, CGFloat) = (0.36, 0.55, 1.0)

    private let rig = SCNNode()
    private let head = SCNNode()
    private let armL = SCNNode()
    private let armR = SCNNode()
    private let eyes = SCNNode()
    private let happy = SCNNode()
    /// Materials that take the mood color.
    private var tints: [SCNMaterial] = []
    /// Character-specific motion on top of the shared poses (e.g. Nori's tail).
    private var extra: ((CGFloat, Mood) -> Void)?
    /// Turned a little sideways (the duck faces right).
    private var baseYaw: CGFloat = 0
    /// How far the head turns while watching agents work (the owl turns further).
    private var headTurn: CGFloat = 0.35
    /// Where a festival hat sits on the head, its size, and what it replaces (the duck's cap).
    private var hatAt = SCNVector3(0, 0.5, 0)
    private var hatScale: CGFloat = 1
    private var hatHides: [SCNNode] = []
    /// Festival costume: a hat on the head, and props on the floor.
    private var costume: Costume?
    private let costumeHat = SCNNode()
    private let costumeFloor = SCNNode()
    private var costumeMotion: ((CGFloat) -> Void)?
    /// Idle tricks on, where the mouse is (-1…1 each way; nil = not following), and walking (-1 left, 1 right).
    private var tricks = false
    private var gaze: CGPoint?
    private var smoothGaze = CGPoint.zero
    private var walking: CGFloat = 0

    /// Every number that makes up a pose, so a change of pose can blend instead of snap.
    private struct Pose {
        var y: CGFloat = 0, roll: CGFloat = 0, yaw: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1
        var headYaw: CGFloat = 0, headPitch: CGFloat = 0, headRoll: CGFloat = 0
        var outL: CGFloat = 0.14, outR: CGFloat = 0.14, fwdL: CGFloat = 0, fwdR: CGFloat = 0

        func blended(to b: Pose, _ k: CGFloat) -> Pose {
            func l(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * k }
            // Turning: the short way round (a full spin ends where it started).
            let dYaw = atan2(sin(b.yaw - yaw), cos(b.yaw - yaw))
            return Pose(y: l(y, b.y), roll: l(roll, b.roll), yaw: yaw + dYaw * k, sx: l(sx, b.sx), sy: l(sy, b.sy),
                        headYaw: l(headYaw, b.headYaw), headPitch: l(headPitch, b.headPitch), headRoll: l(headRoll, b.headRoll),
                        outL: l(outL, b.outL), outR: l(outR, b.outR), fwdL: l(fwdL, b.fwdL), fwdR: l(fwdR, b.fwdR))
        }
    }
    /// The pose being shown, what it's blending from, and since when.
    private var shownPose = Pose()
    private var blendFrom = Pose()
    private var blendStart: CGFloat = -10
    private var poseKey = ""

    init(character: BuddyCharacterKind) {
        super.init()
        switch character {
        case .nori: buildNori()
        case .bolt: buildBolt()
        case .quackers: buildQuackers()
        case .sage: buildSage()
        case .nova: buildNova()
        }
        scene.rootNode.addChildNode(rig)
        costumeHat.position = hatAt
        let k = hatScale * 1.45
        costumeHat.scale = SCNVector3(k, k, k)
        head.addChildNode(costumeHat)
        scene.rootNode.addChildNode(costumeFloor)
        buildStudio()
    }

    /// Jump straight to the mood's color (no fade), for still images.
    func snapColor() {
        lock.lock()
        current = target
        lock.unlock()
    }

    func set(tricks: Bool, gaze: CGPoint?, walking: CGFloat) {
        lock.lock()
        self.tricks = tricks
        self.gaze = gaze
        self.walking = walking
        lock.unlock()
    }

    func set(gaze: CGPoint?) {
        lock.lock()
        self.gaze = gaze
        lock.unlock()
    }

    func set(mood: Mood, activity: BuddyActivity? = nil) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (NSColor(mood.color).usingColorSpace(.sRGB) ?? .systemBlue).getRed(&r, green: &g, blue: &b, alpha: &a)
        lock.lock()
        self.mood = mood
        self.activity = activity
        target = (r, g, b)
        lock.unlock()
    }

    // MARK: Building blocks

    private func pbr(_ hex: UInt32, metal: CGFloat = 0, rough: CGFloat = 0.5, clearcoat: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(hex)
        m.metalness.contents = metal
        m.roughness.contents = rough
        if clearcoat > 0 {
            m.clearCoat.contents = clearcoat
            m.clearCoatRoughness.contents = 0.12
        }
        return m
    }

    private func glow(_ hex: UInt32) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor(hex)
        return m
    }

    private func node(_ g: SCNGeometry, _ m: SCNMaterial, at p: SCNVector3,
                      scale: SCNVector3 = SCNVector3(1, 1, 1), euler: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = p
        n.scale = scale
        n.eulerAngles = euler
        n.castsShadow = true
        return n
    }

    private func sphere(_ r: CGFloat, _ m: SCNMaterial, at p: SCNVector3, scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
        let g = SCNSphere(radius: r)
        g.segmentCount = 40
        return node(g, m, at: p, scale: scale)
    }

    private func cylinder(_ r: CGFloat, _ h: CGFloat, _ m: SCNMaterial, at p: SCNVector3,
                          euler: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
        let g = SCNCylinder(radius: r, height: h)
        g.radialSegmentCount = 32
        return node(g, m, at: p, euler: euler)
    }

    /// A "^" eye made of small beads along an arc.
    private func happyEye(_ m: SCNMaterial, at p: SCNVector3, radius: CGFloat = 0.08) -> SCNNode {
        let n = SCNNode()
        n.position = p
        for i in 0...8 {
            let a = CGFloat.pi * CGFloat(i) / 8
            n.addChildNode(sphere(radius * 0.3, m, at: SCNVector3(cos(a) * radius, sin(a) * radius - radius * 0.4, 0)))
        }
        return n
    }

    // MARK: Nori (cat)

    private func buildNori() {
        let fur = pbr(0xF09A52, rough: 0.92)
        let cream = pbr(0xFFF0DC, rough: 0.92)
        let pink = pbr(0xFF9DB2, rough: 0.55)
        let collar = pbr(0x5B8CFF, rough: 0.35, clearcoat: 0.7)
        let bell = pbr(0xFFD166, metal: 0.9, rough: 0.22)
        let ink = pbr(0x0D0C14, rough: 0.06, clearcoat: 1)
        let white = pbr(0xFFFFFF, rough: 0.15)
        let whisker = pbr(0x6B5A4E, rough: 0.6)
        tints = [collar]

        rig.addChildNode(sphere(0.6, fur, at: SCNVector3(0, 0.6, 0), scale: SCNVector3(1, 0.95, 0.9)))
        rig.addChildNode(sphere(0.38, cream, at: SCNVector3(0, 0.58, 0.36), scale: SCNVector3(1, 1.1, 0.6)))

        // Tail: a smooth chain of spheres along a curve, swinging from its base.
        let tail = SCNNode()
        tail.position = SCNVector3(0.38, 0.32, -0.3)
        let pts: [SIMD3<Float>] = [[0, 0, 0], [0.4, 0.12, -0.12], [0.52, 0.6, -0.1], [0.32, 0.95, -0.05]]
        for p in catmullRom(pts, samples: 26) {
            tail.addChildNode(sphere(0.09, fur, at: SCNVector3(CGFloat(p.x), CGFloat(p.y), CGFloat(p.z))))
        }
        rig.addChildNode(tail)

        // Front legs hang from shoulder pivots (they act as the arms).
        for (leg, x) in [(armL, CGFloat(-0.24)), (armR, CGFloat(0.24))] {
            leg.position = SCNVector3(x, 0.62, 0.32)
            leg.addChildNode(cylinder(0.105, 0.5, fur, at: SCNVector3(0, -0.25, 0)))
            leg.addChildNode(sphere(0.13, cream, at: SCNVector3(0, -0.5, 0.03), scale: SCNVector3(1.1, 0.7, 1.25)))
            rig.addChildNode(leg)
        }

        // Collar and bell
        rig.addChildNode(node(SCNTorus(ringRadius: 0.34, pipeRadius: 0.05), collar, at: SCNVector3(0, 1.02, 0.02)))
        rig.addChildNode(sphere(0.07, bell, at: SCNVector3(0, 0.95, 0.36)))

        // Head
        head.position = SCNVector3(0, 1.42, 0.05)
        head.addChildNode(sphere(0.56, fur, at: SCNVector3(0, 0, 0), scale: SCNVector3(1.12, 0.95, 0.95)))
        head.addChildNode(sphere(0.2, cream, at: SCNVector3(0, -0.17, 0.43), scale: SCNVector3(1.35, 0.85, 0.8)))
        head.addChildNode(sphere(0.05, pink, at: SCNVector3(0, -0.08, 0.57), scale: SCNVector3(1.3, 0.8, 0.8)))
        for s: CGFloat in [-1, 1] {
            head.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.2, height: 0.36), fur,
                                   at: SCNVector3(s * 0.34, 0.5, 0), euler: SCNVector3(0, 0, -s * 0.35)))
            head.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.12, height: 0.24), pink,
                                   at: SCNVector3(s * 0.33, 0.47, 0.08), euler: SCNVector3(0, 0, -s * 0.35)))
            for dy: CGFloat in [-0.05, 0.05] {
                head.addChildNode(cylinder(0.006, 0.42, whisker, at: SCNVector3(s * 0.36, -0.15 + dy, 0.42),
                                           euler: SCNVector3(0, s * 0.3, CGFloat.pi / 2 + s * dy * 2)))
            }
        }
        for x: CGFloat in [-0.2, 0.2] {
            eyes.addChildNode(sphere(0.085, ink, at: SCNVector3(x, 0.05, 0.47), scale: SCNVector3(1, 1.25, 0.6)))
            eyes.addChildNode(sphere(0.025, white, at: SCNVector3(x + 0.03, 0.1, 0.52)))
            happy.addChildNode(happyEye(ink, at: SCNVector3(x, 0.03, 0.5)))
        }
        finishHead()

        extra = { t, mood in
            let speed: CGFloat = mood == .working ? 9 : mood == .celebrating ? 12 : 2.4
            tail.eulerAngles = SCNVector3(0, sin(t * speed * 0.5) * 0.2, sin(t * speed) * 0.28)
        }
    }

    // MARK: Quackers (rubber duck)

    private func buildQuackers() {
        let plastic = pbr(0xFFC928, rough: 0.2, clearcoat: 1)
        let beak = pbr(0xFF8A1F, rough: 0.28, clearcoat: 0.9)
        let cap = pbr(0x5B8CFF, rough: 0.3, clearcoat: 0.8)
        let ink = pbr(0x0D0C14, rough: 0.06, clearcoat: 1)
        let white = pbr(0xFFFFFF, rough: 0.15)
        tints = [cap]
        baseYaw = -0.62

        rig.addChildNode(sphere(0.8, plastic, at: SCNVector3(0, 0.55, 0), scale: SCNVector3(1.12, 0.68, 0.85)))
        rig.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.28, height: 0.5), plastic,
                              at: SCNVector3(-0.86, 0.82, 0), euler: SCNVector3(0, 0, 2.3)))
        let wingL = SCNNode(), wingR = SCNNode()
        for (wing, z) in [(wingL, CGFloat(0.62)), (wingR, CGFloat(-0.62))] {
            wing.position = SCNVector3(-0.05, 0.75, z)
            wing.addChildNode(sphere(0.32, plastic, at: SCNVector3(-0.05, -0.05, 0), scale: SCNVector3(1.25, 0.55, 0.28)))
            rig.addChildNode(wing)
        }
        head.position = SCNVector3(0.45, 1.25, 0)
        head.addChildNode(sphere(0.46, plastic, at: SCNVector3(0, 0, 0)))
        head.addChildNode(sphere(0.22, beak, at: SCNVector3(0.45, -0.06, 0), scale: SCNVector3(1.45, 0.4, 1)))
        head.addChildNode(sphere(0.2, beak, at: SCNVector3(0.42, -0.14, 0), scale: SCNVector3(1.3, 0.3, 0.9)))
        let dome = sphere(0.31, cap, at: SCNVector3(0, 0.33, 0), scale: SCNVector3(1, 0.62, 1))
        let brim = node(SCNCylinder(radius: 0.3, height: 0.04), cap, at: SCNVector3(0.18, 0.31, 0), scale: SCNVector3(1.25, 1, 1))
        head.addChildNode(dome)
        head.addChildNode(brim)
        hatHides = [dome, brim]
        hatAt = SCNVector3(0, 0.36, 0); hatScale = 0.85
        for z: CGFloat in [0.21, -0.21] {
            eyes.addChildNode(sphere(0.07, ink, at: SCNVector3(0.33, 0.1, z), scale: SCNVector3(1, 1.3, 1)))
            eyes.addChildNode(sphere(0.02, white, at: SCNVector3(0.38, 0.15, z * 1.08)))
        }
        happy.addChildNode(happyEye(ink, at: SCNVector3(0.36, 0.08, 0.24), radius: 0.07))
        finishHead()

        // It floats on a little pond.
        let water = SCNMaterial()
        water.lightingModel = .physicallyBased
        water.diffuse.contents = NSColor(0x67BFE9)
        water.roughness.contents = 0.08
        water.clearCoat.contents = 1
        water.transparency = 0.62
        let pond = node(SCNCylinder(radius: 1.35, height: 0.02), water, at: SCNVector3(0, 0.3, 0))
        pond.castsShadow = false
        scene.rootNode.addChildNode(pond)

        extra = { [unowned self] t, mood in
            let flap: CGFloat = mood == .working ? sin(t * 16) * 0.35 : mood == .celebrating ? sin(t * 22) * 0.6 : sin(t * 2) * 0.05
            wingL.eulerAngles = SCNVector3(-abs(flap), 0, 0)
            wingR.eulerAngles = SCNVector3(abs(flap), 0, 0)
            pond.position = SCNVector3(0, 0.3 + sin(t * 1.6) * 0.015, 0)
            if mood != .celebrating {
                let p = self.rig.position
                self.rig.position = SCNVector3(p.x, p.y + sin(t * (mood == .working ? 7 : 1.8)) * 0.03, p.z)
            }
            if mood == .idle || mood == .stretching {
                let e = self.rig.eulerAngles
                self.rig.eulerAngles = SCNVector3(e.x, e.y, e.z + sin(t * 1.4) * 0.05)
            }
        }
    }

    // MARK: Sage (owl)

    private func buildSage() {
        let feather = pbr(0x86644A, rough: 0.88)
        let belly = pbr(0xEADBC3, rough: 0.92)
        let disc = pbr(0xFAF6EE, rough: 0.6)
        let iris = pbr(0x5B8CFF, rough: 0.12, clearcoat: 1)
        let beak = pbr(0xF2A33A, rough: 0.35, clearcoat: 0.4)
        let ink = pbr(0x0D0C14, rough: 0.06, clearcoat: 1)
        let white = pbr(0xFFFFFF, rough: 0.15)
        tints = [iris]
        headTurn = 0.75 // owls turn their heads a long way
        hatAt = SCNVector3(0, 0.42, 0)

        rig.addChildNode(sphere(0.72, feather, at: SCNVector3(0, 0.9, 0), scale: SCNVector3(1, 1.12, 0.9)))
        rig.addChildNode(sphere(0.5, belly, at: SCNVector3(0, 0.8, 0.4), scale: SCNVector3(1, 1.2, 0.55)))
        for x: CGFloat in [-0.2, 0.2] {
            for dx: CGFloat in [-0.07, 0, 0.07] {
                rig.addChildNode(cylinder(0.025, 0.16, beak, at: SCNVector3(x + dx, 0.06, 0.32),
                                          euler: SCNVector3(CGFloat.pi / 2.4, 0, dx * 3)))
            }
        }
        // Wings hang from the shoulders (they act as the arms).
        for (wing, s) in [(armL, CGFloat(-1)), (armR, CGFloat(1))] {
            wing.position = SCNVector3(s * 0.62, 1.3, 0)
            wing.addChildNode(sphere(0.3, feather, at: SCNVector3(s * 0.04, -0.34, 0), scale: SCNVector3(0.55, 1.25, 0.8)))
            rig.addChildNode(wing)
        }
        head.position = SCNVector3(0, 1.75, 0)
        head.addChildNode(sphere(0.58, feather, at: SCNVector3(0, 0, 0), scale: SCNVector3(1.12, 0.84, 0.9)))
        for s: CGFloat in [-1, 1] {
            head.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.13, height: 0.34), feather,
                                   at: SCNVector3(s * 0.42, 0.46, 0.08), euler: SCNVector3(0, 0, -s * 0.5)))
            head.addChildNode(sphere(0.27, disc, at: SCNVector3(s * 0.25, 0.06, 0.48), scale: SCNVector3(1, 1, 0.4)))
        }
        head.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.07, height: 0.2), beak,
                               at: SCNVector3(0, -0.12, 0.6), euler: SCNVector3(CGFloat.pi * 0.92, 0, 0)))
        for x: CGFloat in [-0.25, 0.25] {
            eyes.addChildNode(sphere(0.14, iris, at: SCNVector3(x, 0.06, 0.56), scale: SCNVector3(1, 1, 0.5)))
            eyes.addChildNode(sphere(0.07, ink, at: SCNVector3(x, 0.06, 0.62), scale: SCNVector3(1, 1, 0.5)))
            eyes.addChildNode(sphere(0.026, white, at: SCNVector3(x + 0.045, 0.11, 0.65)))
            happy.addChildNode(happyEye(ink, at: SCNVector3(x, 0.03, 0.62), radius: 0.09))
        }
        finishHead()
    }

    // MARK: Nova (astronaut)

    private func buildNova() {
        let suit = pbr(0xF4F6FB, rough: 0.62)
        let helmet = pbr(0xF8F9FD, rough: 0.3, clearcoat: 1)
        let seam = pbr(0xC5CCDC, rough: 0.6)
        let visor = pbr(0x18203F, metal: 1, rough: 0.04)
        let moodGlow = glow(0x5B8CFF)
        let glove = pbr(0x5B8CFF, rough: 0.45)
        let eyeGlow = glow(0x8DF3FF)
        tints = [moodGlow, glove]

        rig.addChildNode(node(SCNBox(width: 0.8, height: 0.8, length: 0.36, chamferRadius: 0.08), seam,
                              at: SCNVector3(0, 0.98, -0.42)))
        for x: CGFloat in [-0.2, 0.2] {
            rig.addChildNode(cylinder(0.15, 0.4, suit, at: SCNVector3(x, 0.32, 0)))
            rig.addChildNode(sphere(0.18, seam, at: SCNVector3(x, 0.1, 0.05), scale: SCNVector3(1, 0.6, 1.3)))
        }
        rig.addChildNode(sphere(0.55, suit, at: SCNVector3(0, 0.88, 0), scale: SCNVector3(1, 1.05, 0.85)))
        rig.addChildNode(node(SCNBox(width: 0.36, height: 0.22, length: 0.06, chamferRadius: 0.02), seam,
                              at: SCNVector3(0, 0.96, 0.46)))
        rig.addChildNode(sphere(0.045, moodGlow, at: SCNVector3(-0.08, 0.96, 0.5)))
        for (arm, x) in [(armL, CGFloat(-0.56)), (armR, CGFloat(0.56))] {
            arm.position = SCNVector3(x, 1.14, 0)
            arm.addChildNode(cylinder(0.13, 0.45, suit, at: SCNVector3(0, -0.25, 0)))
            arm.addChildNode(sphere(0.15, glove, at: SCNVector3(0, -0.52, 0)))
            rig.addChildNode(arm)
        }
        hatAt = SCNVector3(0, 0.56, 0)
        head.position = SCNVector3(0, 1.78, 0)
        head.addChildNode(sphere(0.62, helmet, at: SCNVector3(0, 0, 0)))
        head.addChildNode(sphere(0.5, visor, at: SCNVector3(0, -0.02, 0.24), scale: SCNVector3(1.02, 0.78, 0.84)))
        head.addChildNode(node(SCNTorus(ringRadius: 0.47, pipeRadius: 0.035), moodGlow, at: SCNVector3(0, -0.02, 0.52),
                               scale: SCNVector3(1.1, 1, 0.84), euler: SCNVector3(CGFloat.pi / 2, 0, 0)))
        head.addChildNode(cylinder(0.02, 0.32, seam, at: SCNVector3(0.34, 0.64, 0), euler: SCNVector3(0, 0, -0.4)))
        head.addChildNode(sphere(0.07, moodGlow, at: SCNVector3(0.42, 0.8, 0)))
        for x: CGFloat in [-0.17, 0.17] {
            eyes.addChildNode(sphere(0.06, eyeGlow, at: SCNVector3(x, 0.03, 0.66), scale: SCNVector3(1, 1.4, 0.4)))
            happy.addChildNode(happyEye(eyeGlow, at: SCNVector3(x, 0, 0.67), radius: 0.07))
        }
        finishHead()

        // Zero gravity: drifts up and down, gently turning.
        extra = { [unowned self] t, mood in
            guard mood != .celebrating else { return }
            let p = self.rig.position
            self.rig.position = SCNVector3(p.x, p.y + 0.18 + sin(t * (mood == .working ? 3 : 1.2)) * 0.08, p.z)
            let e = self.rig.eulerAngles
            self.rig.eulerAngles = SCNVector3(e.x, e.y, e.z + sin(t * 0.9) * 0.07)
        }
    }

    // MARK: Following the mouse (main thread)

    private var gazeTimer: Timer?
    private(set) var lastGaze: CGPoint?

    /// While on, reads the mouse 15 times a second and turns the head toward it.
    func followMouse(in view: NSView, _ on: Bool) {
        guard on != (gazeTimer != nil) else { return }
        gazeTimer?.invalidate()
        gazeTimer = nil
        lastGaze = nil
        set(gaze: nil)
        guard on else { return }
        gazeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self, weak view] _ in
            guard let self, let view, let window = view.window else { return }
            let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
            let m = NSEvent.mouseLocation
            let dx = (m.x - frame.midX) / 500, dy = (m.y - (frame.minY + frame.height * 0.72)) / 380
            let g = CGPoint(x: max(-1, min(1, dx)), y: max(-1, min(1, dy)))
            self.lastGaze = g
            self.set(gaze: g)
        }
    }

    // MARK: Festival costumes

    func set(costume new: Costume?) {
        guard new != costume else { return }
        costume = new
        costumeHat.childNodes.forEach { $0.removeFromParentNode() }
        costumeFloor.childNodes.forEach { $0.removeFromParentNode() }
        for n in hatHides { n.isHidden = new.map(Self.isHat) ?? false }
        var motion: ((CGFloat) -> Void)?
        switch new {
        case .partyHat?: motion = buildPartyHat()
        case .santaHat?: buildSantaHat()
        case .witchHat?: motion = buildWitchHat()
        case .diya?: motion = buildDiyas()
        case .holi?: motion = buildHoli()
        case .flag?: motion = buildFlag()
        case nil: break
        }
        lock.lock()
        costumeMotion = motion
        lock.unlock()
    }

    private static func isHat(_ c: Costume) -> Bool { [.partyHat, .santaHat, .witchHat].contains(c) }

    /// A texture of vertical stripes (wraps around a cone as spirals of color).
    private static func stripes(_ colors: [NSColor]) -> NSImage {
        let size = NSSize(width: 256, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        let w = size.width / CGFloat(colors.count * 3)
        for i in 0..<(colors.count * 3) {
            colors[i % colors.count].setFill()
            let x = CGFloat(i) * w
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: 0)); path.line(to: NSPoint(x: x + w, y: 0))
            path.line(to: NSPoint(x: x + w + 40, y: size.height)); path.line(to: NSPoint(x: x + 40, y: size.height))
            path.close(); path.fill()
            path.transform(using: AffineTransform(translationByX: -size.width, byY: 0)); path.fill()
        }
        image.unlockFocus()
        return image
    }

    private func buildPartyHat() -> (CGFloat) -> Void {
        let paper = pbr(0xFFD166, rough: 0.45, clearcoat: 0.6)
        paper.diffuse.contents = Self.stripes([NSColor(0xFF5E8A), NSColor(0xFFD166), NSColor(0x5B8CFF)])
        let gold = pbr(0xFFD166, metal: 0.9, rough: 0.25)
        let hat = SCNNode()
        hat.eulerAngles = SCNVector3(0, 0, -0.22)
        hat.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.22, height: 0.5), paper, at: SCNVector3(0, 0.24, 0)))
        let pom = sphere(0.07, gold, at: SCNVector3(0, 0.5, 0))
        hat.addChildNode(pom)
        costumeHat.addChildNode(hat)
        return { t in let k = 1 + 0.15 * sin(t * 6); pom.scale = SCNVector3(k, k, k) }
    }

    private func buildSantaHat() {
        let red = pbr(0xD62839, rough: 0.85)
        let fluff = pbr(0xFFFFFF, rough: 0.95)
        let hat = SCNNode()
        hat.eulerAngles = SCNVector3(0, 0, -0.18)
        hat.addChildNode(node(SCNCone(topRadius: 0.05, bottomRadius: 0.3, height: 0.42), red, at: SCNVector3(0, 0.2, 0)))
        // The tip flops over to one side.
        hat.addChildNode(node(SCNCone(topRadius: 0.02, bottomRadius: 0.06, height: 0.24), red,
                              at: SCNVector3(0.1, 0.44, 0), euler: SCNVector3(0, 0, -1.1)))
        hat.addChildNode(sphere(0.08, fluff, at: SCNVector3(0.22, 0.4, 0)))
        hat.addChildNode(node(SCNTorus(ringRadius: 0.3, pipeRadius: 0.07), fluff, at: SCNVector3(0, 0.0, 0)))
        costumeHat.addChildNode(hat)
        // A present at its feet.
        let box = pbr(0x2EC27E, rough: 0.5, clearcoat: 0.5)
        let ribbon = pbr(0xFFD166, metal: 0.6, rough: 0.3)
        let gift = SCNNode()
        gift.position = SCNVector3(-1.0, 0.2, 0.35)
        gift.eulerAngles = SCNVector3(0, 0.4, 0)
        gift.addChildNode(node(SCNBox(width: 0.4, height: 0.4, length: 0.4, chamferRadius: 0.03), box, at: SCNVector3(0, 0, 0)))
        gift.addChildNode(node(SCNBox(width: 0.42, height: 0.42, length: 0.08, chamferRadius: 0.01), ribbon, at: SCNVector3(0, 0, 0)))
        gift.addChildNode(node(SCNBox(width: 0.08, height: 0.42, length: 0.42, chamferRadius: 0.01), ribbon, at: SCNVector3(0, 0, 0)))
        for s: CGFloat in [-1, 1] {
            gift.addChildNode(node(SCNTorus(ringRadius: 0.07, pipeRadius: 0.025), ribbon, at: SCNVector3(s * 0.06, 0.24, 0),
                                   euler: SCNVector3(CGFloat.pi / 2, 0, s * 0.5)))
        }
        costumeFloor.addChildNode(gift)
    }

    private func buildWitchHat() -> (CGFloat) -> Void {
        let felt = pbr(0x3B2A5C, rough: 0.9)
        let band = pbr(0xFF8A1F, rough: 0.5)
        let hat = SCNNode()
        hat.eulerAngles = SCNVector3(0, 0, 0.15)
        hat.addChildNode(cylinder(0.5, 0.03, felt, at: SCNVector3(0, 0.02, 0)))
        hat.addChildNode(node(SCNCone(topRadius: 0.02, bottomRadius: 0.27, height: 0.6), felt, at: SCNVector3(0, 0.32, 0)))
        hat.addChildNode(cylinder(0.255, 0.07, band, at: SCNVector3(0, 0.08, 0)))
        costumeHat.addChildNode(hat)
        // A jack-o'-lantern with a flickering glow.
        let pumpkin = pbr(0xF77F00, rough: 0.6, clearcoat: 0.3)
        let stem = pbr(0x4F772D, rough: 0.8)
        let flame = glow(0xFFD166)
        let jack = SCNNode()
        jack.position = SCNVector3(-1.05, 0.29, 0.4)
        jack.scale = SCNVector3(1.3, 1.3, 1.3)
        jack.eulerAngles = SCNVector3(0, 0.35, 0)
        jack.addChildNode(sphere(0.28, pumpkin, at: SCNVector3(0, 0, 0), scale: SCNVector3(1.15, 0.82, 1)))
        jack.addChildNode(cylinder(0.04, 0.12, stem, at: SCNVector3(0, 0.27, 0)))
        for x: CGFloat in [-0.1, 0.1] {
            jack.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.07), flame,
                                   at: SCNVector3(x, 0.06, 0.25), euler: SCNVector3(CGFloat.pi / 2.4, 0, 0)))
        }
        jack.addChildNode(sphere(0.1, flame, at: SCNVector3(0, -0.07, 0.24), scale: SCNVector3(1.3, 0.35, 0.3)))
        costumeFloor.addChildNode(jack)
        return { t in
            flame.diffuse.contents = NSColor(0xFFD166).blended(withFraction: 0.35 + 0.35 * sin(t * 13) * sin(t * 7), of: .orange)
        }
    }

    private func buildDiyas() -> (CGFloat) -> Void {
        let clay = pbr(0xB5541C, rough: 0.75)
        let paint = pbr(0xFFD166, metal: 0.5, rough: 0.35)
        let flame = glow(0xFFC94A)
        var flames: [SCNNode] = []
        var lights: [SCNLight] = []
        for (x, z) in [(CGFloat(-1.0), CGFloat(0.45)), (1.0, 0.45), (-0.55, 0.85)] {
            let diya = SCNNode()
            diya.position = SCNVector3(x, 0, z)
            diya.scale = SCNVector3(1.4, 1.4, 1.4)
            diya.addChildNode(node(SCNCone(topRadius: 0.2, bottomRadius: 0.1, height: 0.12), clay, at: SCNVector3(0, 0.06, 0)))
            diya.addChildNode(node(SCNTorus(ringRadius: 0.19, pipeRadius: 0.02), paint, at: SCNVector3(0, 0.12, 0)))
            let f = sphere(0.055, flame, at: SCNVector3(0, 0.22, 0), scale: SCNVector3(0.7, 1.5, 0.7))
            f.castsShadow = false
            diya.addChildNode(f)
            let light = SCNLight()
            light.type = .omni
            light.color = NSColor(0xFFB347)
            light.intensity = 35
            light.attenuationStartDistance = 0
            light.attenuationEndDistance = 0.8
            let ln = SCNNode()
            ln.light = light
            ln.position = SCNVector3(0, 0.3, 0)
            diya.addChildNode(ln)
            flames.append(f); lights.append(light)
            costumeFloor.addChildNode(diya)
        }
        return { t in
            for (i, f) in flames.enumerated() {
                let k = 1 + 0.12 * sin(t * 11 + CGFloat(i) * 2) * sin(t * 5 + CGFloat(i))
                f.scale = SCNVector3(0.7 * k, 1.5 * (2 - k), 0.7 * k)
                lights[i].intensity = 35 * k
            }
        }
    }

    private func buildHoli() -> (CGFloat) -> Void {
        // Clouds of colored powder (gulal) swirling around.
        let colors: [UInt32] = [0xFF4FA3, 0xFFD23F, 0x3BCEAC, 0x5B8CFF, 0xA06CD5, 0xFF8A1F]
        var puffs: [(SCNNode, CGFloat, CGFloat, CGFloat)] = []
        for i in 0..<12 {
            let m = glow(colors[i % colors.count])
            m.transparency = 0.55
            let p = sphere(0.09 + CGFloat(i % 3) * 0.035, m, at: SCNVector3(0, 0, 0))
            p.castsShadow = false
            costumeFloor.addChildNode(p)
            puffs.append((p, CGFloat(i) / 12 * 2 * .pi, 0.3 + CGFloat(i % 4) * 0.45, 1.05 + CGFloat(i % 3) * 0.12))
        }
        // Splashes of color on the floor.
        for (i, c) in colors.enumerated() {
            let m = glow(c)
            m.transparency = 0.45
            let a = CGFloat(i) / CGFloat(colors.count) * 2 * .pi
            let splash = node(SCNCylinder(radius: 0.22, height: 0.005), m, at: SCNVector3(cos(a) * 1.0, 0.01, sin(a) * 0.6 + 0.2),
                              scale: SCNVector3(1.3, 1, 0.8))
            splash.castsShadow = false
            costumeFloor.addChildNode(splash)
        }
        return { t in
            for (p, phase, height, radius) in puffs {
                let a = phase + t * 0.6
                p.position = SCNVector3(cos(a) * radius, height + sin(t * 1.3 + phase) * 0.12, sin(a) * radius * 0.6)
            }
        }
    }

    /// The tricolor, fluttering on a pole beside the buddy.
    private func buildFlag() -> (CGFloat) -> Void {
        let size = NSSize(width: 300, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(0xFF9933).setFill(); NSRect(x: 0, y: 133, width: 300, height: 67).fill()
        NSColor.white.setFill(); NSRect(x: 0, y: 67, width: 300, height: 66).fill()
        NSColor(0x138808).setFill(); NSRect(x: 0, y: 0, width: 300, height: 67).fill()
        NSColor(0x000080).setStroke()
        let wheel = NSBezierPath(ovalIn: NSRect(x: 124, y: 74, width: 52, height: 52))
        wheel.lineWidth = 4; wheel.stroke()
        for i in 0..<24 {
            let a = CGFloat(i) / 24 * 2 * .pi
            let spoke = NSBezierPath()
            spoke.move(to: NSPoint(x: 150, y: 100)); spoke.line(to: NSPoint(x: 150 + cos(a) * 26, y: 100 + sin(a) * 26))
            spoke.lineWidth = 1.5; spoke.stroke()
        }
        image.unlockFocus()

        let pole = pbr(0xC9CED8, metal: 0.8, rough: 0.3)
        let cloth = SCNMaterial()
        cloth.lightingModel = .physicallyBased
        cloth.diffuse.contents = image
        cloth.roughness.contents = 0.85
        cloth.isDoubleSided = true
        let flag = SCNNode()
        flag.position = SCNVector3(-0.95, 0, 0.3)
        flag.addChildNode(cylinder(0.025, 1.9, pole, at: SCNVector3(0, 0.95, 0)))
        flag.addChildNode(sphere(0.045, pbr(0xFFD166, metal: 0.9, rough: 0.2), at: SCNVector3(0, 1.92, 0)))
        let hinge = SCNNode()
        hinge.position = SCNVector3(0, 1.62, 0)
        let plane = SCNPlane(width: 0.66, height: 0.44)
        plane.widthSegmentCount = 8
        let cl = node(plane, cloth, at: SCNVector3(-0.34, 0, 0))
        hinge.addChildNode(cl)
        flag.addChildNode(hinge)
        costumeFloor.addChildNode(flag)
        return { t in hinge.eulerAngles = SCNVector3(0, 0.25 + sin(t * 2.6) * 0.18, sin(t * 3.3) * 0.03) }
    }

    // MARK: Bolt (robot)

    private func buildBolt() {
        let metal = pbr(0xD6DBE6, metal: 0.88, rough: 0.26, clearcoat: 0.4)
        let screen = pbr(0x0A0E19, rough: 0.06, clearcoat: 1)
        let eyeGlow = glow(0x8DF3FF)
        let moodGlow = glow(0x5B8CFF)
        tints = [moodGlow]

        for x: CGFloat in [-0.22, 0.22] {
            rig.addChildNode(cylinder(0.09, 0.3, metal, at: SCNVector3(x, 0.25, 0)))
            rig.addChildNode(sphere(0.16, metal, at: SCNVector3(x, 0.08, 0.05), scale: SCNVector3(1, 0.55, 1.3)))
        }
        rig.addChildNode(sphere(0.55, metal, at: SCNVector3(0, 0.72, 0), scale: SCNVector3(1, 0.85, 0.85)))
        rig.addChildNode(sphere(0.085, moodGlow, at: SCNVector3(0, 0.8, 0.45)))
        for (arm, x) in [(armL, CGFloat(-0.6)), (armR, CGFloat(0.6))] {
            arm.position = SCNVector3(x, 0.98, 0)
            arm.addChildNode(cylinder(0.08, 0.45, metal, at: SCNVector3(0, -0.24, 0)))
            arm.addChildNode(sphere(0.13, metal, at: SCNVector3(0, -0.5, 0)))
            rig.addChildNode(arm)
        }
        hatAt = SCNVector3(0, 0.48, 0); hatScale = 1.1
        head.position = SCNVector3(0, 1.62, 0)
        head.addChildNode(sphere(0.62, metal, at: SCNVector3(0, 0, 0), scale: SCNVector3(1.12, 0.86, 0.9)))
        head.addChildNode(sphere(0.5, screen, at: SCNVector3(0, -0.02, 0.36), scale: SCNVector3(1.1, 0.72, 0.45)))
        for s: CGFloat in [-1, 1] {
            head.addChildNode(cylinder(0.12, 0.12, moodGlow, at: SCNVector3(s * 0.72, 0, 0), euler: SCNVector3(0, 0, CGFloat.pi / 2)))
        }
        head.addChildNode(cylinder(0.025, 0.35, metal, at: SCNVector3(0, 0.66, 0)))
        head.addChildNode(sphere(0.09, moodGlow, at: SCNVector3(0, 0.88, 0)))
        head.addChildNode(sphere(0.05, eyeGlow, at: SCNVector3(0, -0.18, 0.6), scale: SCNVector3(1.8, 0.45, 0.4)))
        for x: CGFloat in [-0.2, 0.2] {
            eyes.addChildNode(sphere(0.075, eyeGlow, at: SCNVector3(x, 0.06, 0.6), scale: SCNVector3(1, 1.35, 0.5)))
            happy.addChildNode(happyEye(eyeGlow, at: SCNVector3(x, 0.05, 0.6)))
        }
        finishHead()
    }

    private func finishHead() {
        happy.isHidden = true
        head.addChildNode(eyes)
        head.addChildNode(happy)
        rig.addChildNode(head)
    }

    /// Points along a Catmull-Rom spline through `pts`.
    private func catmullRom(_ pts: [SIMD3<Float>], samples: Int) -> [SIMD3<Float>] {
        let p = [pts[0]] + pts + [pts[pts.count - 1]]
        var out: [SIMD3<Float>] = []
        for i in 0..<samples {
            let u = Float(i) / Float(samples - 1) * Float(pts.count - 1)
            let seg = min(Int(u), pts.count - 2)
            let t = u - Float(seg)
            let (p0, p1, p2, p3) = (p[seg], p[seg + 1], p[seg + 2], p[seg + 3])
            let t2 = t * t, t3 = t2 * t
            let a = 2 * p1
            let b = (p2 - p0) * t
            let c = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
            let d = (3 * p1 - p0 - 3 * p2 + p3) * t3
            out.append(0.5 * (a + b + c + d))
        }
        return out
    }

    // MARK: Studio: floor shadow, lights, reflections, camera

    private func buildStudio() {
        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorMat = SCNMaterial()
        floorMat.lightingModel = .shadowOnly
        floor.materials = [floorMat]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        scene.lightingEnvironment.contents = Buddy3DScene.studioImage()
        scene.lightingEnvironment.intensity = 1.3

        let key = SCNLight()
        key.type = .directional
        key.intensity = 1100
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 6
        key.shadowSampleCount = 16
        key.shadowColor = NSColor(white: 0, alpha: 0.28)
        key.automaticallyAdjustsShadowProjection = true
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(2.5, 5, 4)
        keyNode.look(at: SCNVector3(0, 0.8, 0))
        scene.rootNode.addChildNode(keyNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 650
        rim.color = NSColor(0xCFE0FF)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(-3, 3, -4)
        rimNode.look(at: SCNVector3(0, 1, 0))
        scene.rootNode.addChildNode(rimNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 250
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.1
        camera.zFar = 50
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.5, 7.6)
        cameraNode.look(at: SCNVector3(0, 1.12, 0))
        scene.rootNode.addChildNode(cameraNode)
    }

    /// A tiny "photo studio" to reflect: light ceiling, softboxes, darker floor.
    static func studioImage() -> NSImage {
        let size = NSSize(width: 512, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor(white: 0.22, alpha: 1), NSColor(white: 0.42, alpha: 1), NSColor(white: 0.92, alpha: 1)],
                   atLocations: [0, 0.5, 1], colorSpace: .sRGB)?
            .draw(in: NSRect(origin: .zero, size: size), angle: 90)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 70, y: 176, width: 130, height: 46), xRadius: 12, yRadius: 12).fill()
        NSColor(0xDBE6FF).setFill()
        NSBezierPath(roundedRect: NSRect(x: 300, y: 128, width: 96, height: 58), xRadius: 10, yRadius: 10).fill()
        NSColor(0xFFF2DC).setFill()
        NSBezierPath(roundedRect: NSRect(x: 430, y: 110, width: 60, height: 40), xRadius: 8, yRadius: 8).fill()
        image.unlockFocus()
        return image
    }

    // MARK: Animation (runs on SceneKit's render thread)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        let mood = self.mood
        let activity = self.activity
        let target = self.target
        let tricks = self.tricks, gaze = self.gaze, walking = self.walking
        lock.unlock()

        let k: CGFloat = 0.08
        current = (current.0 + (target.0 - current.0) * k,
                   current.1 + (target.1 - current.1) * k,
                   current.2 + (target.2 - current.2) * k)
        let pulse: CGFloat = mood == .waiting ? 0.75 + 0.25 * CGFloat(sin(time * 12)) : 1
        let tint = NSColor(srgbRed: current.0 * pulse, green: current.1 * pulse, blue: current.2 * pulse, alpha: 1)
        for m in tints { m.diffuse.contents = tint }

        let t = CGFloat(time)
        var y: CGFloat = 0, roll: CGFloat = 0, yaw: CGFloat = 0
        var scale = SCNVector3(1, 1, 1)
        var headYaw: CGFloat = 0, headPitch: CGFloat = 0, headRoll: CGFloat = 0
        var outL: CGFloat = 0.14, outR: CGFloat = 0.14, fwdL: CGFloat = 0, fwdR: CGFloat = 0

        switch mood {
        case .idle:
            y = (sin(t * 2.4) + 1) * 0.03
            outL = 0.14 + sin(t * 1.6) * 0.06; outR = outL
            headYaw = sin(t * 0.7) * 0.2
        case .working:
            y = abs(sin(t * 8)) * 0.035
            fwdL = -0.95 + sin(t * 16) * 0.28
            fwdR = -0.95 + sin(t * 16 + .pi) * 0.28
            headYaw = sin(t * 2.4) * headTurn; headPitch = 0.12
        case .waiting:
            roll = sin(t * 2.2) * 0.12
            outR = 2.5 + sin(t * 7) * 0.15
            headRoll = 0.18
        case .celebrating:
            let p = (t * 1.15).truncatingRemainder(dividingBy: 1)
            y = 4 * p * (1 - p) * 0.55
            let squash: CGFloat = p < 0.08 || p > 0.92 ? 0.07 : 0
            scale = SCNVector3(1 + squash, 1 - squash, 1 + squash)
            yaw = sin(t * 2) * 0.35
            outL = 2.55 + sin(t * 14) * 0.25; outR = outL
        case .stretching:
            roll = sin(t * 1.2) * 0.08
            scale = SCNVector3(1, 1 + (sin(t * 1.2) + 1) * 0.03, 1)
            outL = 2.75 + sin(t * 1.2) * 0.12; outR = outL
            headPitch = -0.2
        }

        var eyesClosed = false, happyOverride: Bool?
        var trick = -1

        // Idle: walk along the screen, or now and then do a little trick.
        if mood == .idle && activity == nil {
            if walking != 0 {
                let step = sin(t * 9)
                y = abs(step) * 0.06
                yaw = walking * 1.15
                roll = step * 0.04
                fwdL = step * 0.7; fwdR = -step * 0.7
                outL = 0.2; outR = 0.2
                headYaw = 0; headPitch = 0.05
            } else if tricks {
                let period: CGFloat = 26
                let cycle = t.truncatingRemainder(dividingBy: period)
                if cycle < 3 {
                    let p = cycle / 3, bump = sin(p * .pi)
                    trick = Int(t / period) % 5
                    switch trick {
                    case 0: yaw = (1 - cos(p * .pi)) * .pi                       // spin round (chasing its tail)
                    case 1: outL = 2.7 * bump; outR = outL                        // big stretch
                        scale = SCNVector3(1, 1 + 0.05 * bump, 1); happyOverride = true
                    case 2: headPitch = -0.35 * bump; eyesClosed = p > 0.25 && p < 0.8  // yawn
                    case 3: outR = (2.3 + sin(t * 12) * 0.25) * bump              // wave
                    default: y = abs(sin(p * 2 * .pi)) * 0.25                      // two little hops
                    }
                }
            }
        }

        // Look toward the mouse.
        if let g = gaze, activity == nil, mood != .celebrating, walking == 0 {
            smoothGaze.x += (g.x - smoothGaze.x) * 0.12
            smoothGaze.y += (g.y - smoothGaze.y) * 0.12
            headYaw = headYaw * 0.4 + smoothGaze.x * 0.55
            headPitch -= smoothGaze.y * 0.3
        } else {
            smoothGaze.x *= 0.9; smoothGaze.y *= 0.9
        }
        eyes.position = SCNVector3(smoothGaze.x * 0.05, smoothGaze.y * 0.035, 0)

        // Acting out a situation overrides the mood pose.
        switch activity {
        case .eat?:
            // Paws up to the mouth, head dipping to chew.
            y = 0; roll = 0; yaw = 0; scale = SCNVector3(1, 1, 1)
            outL = 0.35; outR = 0.35
            fwdL = -1.55 + sin(t * 9) * 0.12; fwdR = -1.55 + sin(t * 9 + 1) * 0.12
            headPitch = 0.22 + abs(sin(t * 9)) * 0.06; headYaw = 0; headRoll = 0
            happyOverride = true
        case .drink?:
            // One paw lifts the cup, head tips back to sip.
            y = 0; roll = 0; yaw = 0; scale = SCNVector3(1, 1, 1)
            outL = 0.14; outR = 0.3
            fwdL = 0; fwdR = -1.75 + sin(t * 2) * 0.05
            headPitch = -0.22 + sin(t * 2) * 0.04; headYaw = 0; headRoll = 0
            happyOverride = true
        case .sleep?:
            // Head drooped to one side, slow breathing, arms resting.
            y = 0; roll = 0.06; yaw = 0
            scale = SCNVector3(1 + sin(t * 1.3) * 0.015, 1 + sin(t * 1.3) * 0.025, 1)
            outL = 0.05; outR = 0.05; fwdL = 0; fwdR = 0
            headPitch = 0.38; headYaw = 0; headRoll = 0.3
            eyesClosed = true
        case nil:
            break
        }

        // A new pose (mood, activity, trick, walking) blends in over a third of a second.
        let goal = Pose(y: y, roll: roll, yaw: yaw, sx: CGFloat(scale.x), sy: CGFloat(scale.y),
                          headYaw: headYaw, headPitch: headPitch, headRoll: headRoll,
                          outL: outL, outR: outR, fwdL: fwdL, fwdR: fwdR)
        let key = "\(mood)|\(String(describing: activity))|\(trick)|\(walking)"
        if key != poseKey {
            if !poseKey.isEmpty { blendFrom = shownPose; blendStart = t }
            poseKey = key
        }
        let p = min(1, max(0, (t - blendStart) / 0.35))
        let ease = p * p * (3 - 2 * p)
        let pose = p >= 1 ? goal : blendFrom.blended(to: goal, ease)
        shownPose = pose

        rig.position = SCNVector3(0, pose.y, 0)
        rig.eulerAngles = SCNVector3(0, pose.yaw + baseYaw, pose.roll)
        rig.scale = SCNVector3(pose.sx, pose.sy, pose.sx)
        head.eulerAngles = SCNVector3(pose.headPitch, pose.headYaw, pose.headRoll)
        armL.eulerAngles = SCNVector3(pose.fwdL, 0, -pose.outL)
        armR.eulerAngles = SCNVector3(pose.fwdR, 0, pose.outR)

        let isHappy = happyOverride ?? (activity == nil && (mood == .celebrating || mood == .stretching))
        let blink = t.truncatingRemainder(dividingBy: 3.8) < 0.12
        eyes.isHidden = isHappy
        happy.isHidden = !isHappy
        eyes.scale = SCNVector3(1, eyesClosed || blink ? 0.08 : (mood == .waiting ? 1.15 : 1), 1)
        extra?(t, mood)
        lock.lock()
        let motion = costumeMotion
        lock.unlock()
        motion?(t)
    }
}

private extension NSColor {
    convenience init(_ hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Clicks and drags go to the SwiftUI view (open panel / move window), not SceneKit.
final class PassThroughSCNView: SCNView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct Buddy3DView: NSViewRepresentable {
    let character: BuddyCharacterKind
    let mood: Mood
    var activity: BuddyActivity? = nil
    var costume: Costume? = nil
    var tricks = false
    var eyesFollow = false
    var walking: CGFloat = 0

    func makeCoordinator() -> Buddy3DScene { Buddy3DScene(character: character) }

    func makeNSView(context: Context) -> SCNView {
        let view = PassThroughSCNView(frame: .zero, options: nil)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        context.coordinator.set(mood: mood, activity: activity)
        context.coordinator.set(costume: costume)
        context.coordinator.set(tricks: tricks, gaze: nil, walking: walking)
        context.coordinator.followMouse(in: view, eyesFollow)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.set(mood: mood, activity: activity)
        context.coordinator.set(costume: costume)
        context.coordinator.set(tricks: tricks, gaze: context.coordinator.lastGaze, walking: walking)
        context.coordinator.followMouse(in: view, eyesFollow)
        // 30 frames a second looks smooth for poses, gears and gaze; only fast motion (the
        // celebration jump, walking) gets 60. Each extra frame costs battery.
        view.preferredFramesPerSecond = mood == .celebrating || walking != 0 ? 60 : 30
    }
}

/// True inside the off-screen copy used only to measure the window size, so it
/// doesn't spin up a second 3D renderer.
private struct MeasuringKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var isMeasuring: Bool {
        get { self[MeasuringKey.self] }
        set { self[MeasuringKey.self] = newValue }
    }
}
