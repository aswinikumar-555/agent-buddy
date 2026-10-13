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
        buildStudio()
    }

    /// Jump straight to the mood's color (no fade), for still images.
    func snapColor() {
        lock.lock()
        current = target
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
        head.addChildNode(sphere(0.31, cap, at: SCNVector3(0, 0.33, 0), scale: SCNVector3(1, 0.62, 1)))
        head.addChildNode(node(SCNCylinder(radius: 0.3, height: 0.04), cap, at: SCNVector3(0.18, 0.31, 0),
                               scale: SCNVector3(1.25, 1, 1)))
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

        // Acting out a situation overrides the mood pose.
        var eyesClosed = false, happyOverride: Bool?
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

        rig.position = SCNVector3(0, y, 0)
        rig.eulerAngles = SCNVector3(0, yaw + baseYaw, roll)
        rig.scale = scale
        head.eulerAngles = SCNVector3(headPitch, headYaw, headRoll)
        armL.eulerAngles = SCNVector3(fwdL, 0, -outL)
        armR.eulerAngles = SCNVector3(fwdR, 0, outR)

        let isHappy = happyOverride ?? (activity == nil && (mood == .celebrating || mood == .stretching))
        let blink = t.truncatingRemainder(dividingBy: 3.8) < 0.12
        eyes.isHidden = isHappy
        happy.isHidden = !isHappy
        eyes.scale = SCNVector3(1, eyesClosed || blink ? 0.08 : (mood == .waiting ? 1.15 : 1), 1)
        extra?(t, mood)
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
        view.preferredFramesPerSecond = 30
        context.coordinator.set(mood: mood, activity: activity)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.set(mood: mood, activity: activity)
        // Calm moods don't need full frame rate; saves battery.
        view.preferredFramesPerSecond = mood == .idle ? 20 : 30
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
