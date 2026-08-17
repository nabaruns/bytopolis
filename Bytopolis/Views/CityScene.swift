import SceneKit
import AppKit

/// Builds an SCNScene from a `CityLayout`: districts as raised plots, files as buildings
/// sized by bytes, git repos as walled facilities, recent items glowing, and a beacon over
/// the single most-recently-modified "entry". Each node carries its path in `name` for
/// hit-testing.
///
/// The look adapts to the system appearance: a lit night city in dark mode, a bright
/// daytime city in light mode (`dark: false`).
enum CityScene {

    /// Appearance-dependent surfaces (sky, ground, lighting, glow) for one build.
    struct Style {
        let dark: Bool
        var background: NSColor { dark ? hex(0x0D0F17) : hex(0xE8EDF4) }
        var floor: NSColor { dark ? hex(0x1A1C26) : hex(0xD3D9E2) }
        var ambientColor: NSColor {
            dark ? NSColor(calibratedRed: 0.62, green: 0.66, blue: 0.78, alpha: 1)
                 : NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.94, alpha: 1)
        }
        var ambientIntensity: CGFloat { dark ? 550 : 820 }
        var keyIntensity: CGFloat { dark ? 1100 : 1000 }
    }

    static func make(from layout: CityLayout, dark: Bool = true) -> SCNScene {
        let style = Style(dark: dark)
        let scene = SCNScene()
        let root = scene.rootNode
        let side = CGFloat(layout.bounds.width)

        // Ground.
        let floor = SCNBox(width: side + 10, height: 1, length: side + 10, chamferRadius: 0)
        floor.firstMaterial?.diffuse.contents = style.floor
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(Float(side / 2), -0.5, Float(side / 2))
        root.addChildNode(floorNode)

        for n in layout.nodes {
            let cx = Float(n.rect.midX), cz = Float(n.rect.midY)
            let w = n.rect.width, l = n.rect.height
            let plotH: CGFloat = 0.6
            let baseY = Float(n.depth) * 1.4

            switch n.kind {
            case .district, .facility:
                let box = SCNBox(width: w, height: plotH, length: l, chamferRadius: 0)
                box.firstMaterial?.diffuse.contents = plotColor(n, style)
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(cx, baseY + Float(plotH / 2), cz)
                node.name = n.id
                root.addChildNode(node)
                if n.kind == .facility { addWalls(to: root, rect: n.rect, baseY: baseY + Float(plotH), style: style) }

            case .building:
                let h = CGFloat(max(0.6, n.height))
                let inset = min(w, l) * 0.14
                let box = SCNBox(width: max(0.4, w - inset), height: h,
                                 length: max(0.4, l - inset), chamferRadius: 0)
                let mat = SCNMaterial()
                mat.diffuse.contents = buildingColor(n)
                mat.emission.contents = n.isRecent ? glowColor(n, style) : emissionColor(n, style)
                box.materials = [mat]
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(cx, baseY + 0.6 + Float(h) / 2, cz)
                node.name = n.id
                root.addChildNode(node)
                let topY = baseY + 0.6 + Float(h)
                if n.isEntry { addBeacon(to: root, x: cx, y: topY + 5, z: cz) }
            }
        }

        addLighting(to: root, style: style)
        addCamera(to: root, side: Float(side))
        scene.background.contents = style.background
        return scene
    }

    // MARK: - Colors

    private static func hex(_ v: Int) -> NSColor {
        NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Curated palette for file "buildings" (picked by extension) — vivid but cohesive,
    /// and legible against both a dark and a light ground.
    private static let palette: [NSColor] = [
        hex(0x4C9AFF), hex(0x2BD9C8), hex(0x9F7AEA), hex(0xF6AD55),
        hex(0xF56565), hex(0x48BB78), hex(0xED64A6), hex(0x38B2AC),
        hex(0xECC94B), hex(0x667EEA), hex(0xFC8181), hex(0x81E6D9)
    ]

    private static func buildingColor(_ n: CityNode) -> NSColor {
        switch n.category?.reclaim {
        case .safe:    return hex(0x48BB78)   // green — matches legend
        case .caution: return hex(0xF6AD55)   // amber
        default:
            let ext = (n.name as NSString).pathExtension.lowercased()
            if ext.isEmpty { return hex(0x9AA5B1) }   // concrete
            let seed = ext.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFFFFFF }
            return palette[seed % palette.count]
        }
    }

    /// "Newest" glow. Emission is additive, so keep it strong at night and gentle by day so
    /// buildings don't wash out.
    private static func glowColor(_ n: CityNode, _ style: Style) -> NSColor {
        let frac: CGFloat = style.dark ? 0.55 : 0.25
        return buildingColor(n).blended(withFraction: frac, of: .white) ?? .white
    }

    /// Self-illumination so buildings read as a lit night city. In daylight, buildings are
    /// lit by the scene lights instead, so ordinary buildings don't self-glow.
    private static func emissionColor(_ n: CityNode, _ style: Style) -> NSColor {
        style.dark ? (buildingColor(n).blended(withFraction: 0.8, of: .black) ?? .black) : .black
    }

    private static func plotColor(_ n: CityNode, _ style: Style) -> NSColor {
        if n.kind == .facility {
            return style.dark ? hex(0x7C5CD6) : hex(0x8E74E0)   // violet plot for repos
        }
        // Cool slate districts, lightening a touch with depth — dark slate at night, pale by day.
        if style.dark {
            let base = 0.17 + Double(n.depth % 3) * 0.05
            return NSColor(calibratedRed: base * 0.9, green: base, blue: base * 1.25, alpha: 1)
        } else {
            let base = 0.80 - Double(n.depth % 3) * 0.05
            return NSColor(calibratedRed: base * 0.96, green: base, blue: min(1, base * 1.06), alpha: 1)
        }
    }

    // MARK: - Facility walls + beacon

    private static func addWalls(to root: SCNNode, rect: CGRect, baseY: Float, style: Style) {
        let t: CGFloat = 0.7, hWall: CGFloat = 3
        let color = NSColor(calibratedHue: 0.75, saturation: 0.5,
                            brightness: style.dark ? 0.7 : 0.58, alpha: 1)
        func wall(_ w: CGFloat, _ l: CGFloat, _ x: Float, _ z: Float) {
            let box = SCNBox(width: w, height: hWall, length: l, chamferRadius: 0)
            box.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(x, baseY + Float(hWall / 2), z)
            root.addChildNode(node)
        }
        let minX = Float(rect.minX), maxX = Float(rect.maxX)
        let minZ = Float(rect.minY), maxZ = Float(rect.maxY)
        wall(rect.width, t, Float(rect.midX), minZ)
        wall(rect.width, t, Float(rect.midX), maxZ)
        wall(t, rect.height, minX, Float(rect.midY))
        wall(t, rect.height, maxX, Float(rect.midY))
    }

    /// A glowing beacon over the single most-recently-modified node.
    private static func addBeacon(to root: SCNNode, x: Float, y: Float, z: Float) {
        let sphere = SCNSphere(radius: 1.6)
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor.systemYellow
        mat.emission.contents = NSColor.systemYellow
        sphere.materials = [mat]
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(x, y, z)
        let light = SCNLight(); light.type = .omni; light.color = NSColor.systemYellow; light.intensity = 600
        node.light = light
        node.runAction(.repeatForever(.sequence([
            .move(by: SCNVector3(0, 1.2, 0), duration: 0.8),
            .move(by: SCNVector3(0, -1.2, 0), duration: 0.8)
        ])))
        root.addChildNode(node)
    }

    // MARK: - Worker avatars (a little Lego-style figure per agent session)

    /// Builds a blocky minifig for a worker session. The root carries `worker:<id>` for
    /// hit-testing (click the figure → open its session); the inner `figure` node is what
    /// animates, so the root's placement stays put. A "status" bulb over the head is colored
    /// and pulsed by ``applyPhase(_:to:)`` to show working / waiting / stopped / done / failed.
    static func makeWorkerAvatar(agent: AgentWorker.Agent, id: UUID) -> SCNNode {
        let root = SCNNode()
        root.name = "worker:\(id.uuidString)"
        let figure = SCNNode()
        figure.name = "worker:\(id.uuidString)"
        root.addChildNode(figure)

        let bodyColor = agent == .claude ? hex(0xD97757) : hex(0x10A37F)   // Claude clay / Codex green
        let skin = hex(0xF2C14E)                                            // Lego-yellow head
        let limb = bodyColor.blended(withFraction: 0.18, of: .black) ?? bodyColor

        func part(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ color: NSColor,
                  _ x: Float, _ y: Float, _ z: Float, chamfer: CGFloat = 0.15) {
            let g = SCNBox(width: w, height: h, length: d, chamferRadius: chamfer)
            let m = SCNMaterial(); m.diffuse.contents = color; g.materials = [m]
            let n = SCNNode(geometry: g); n.position = SCNVector3(x, y, z)
            n.name = root.name
            figure.addChildNode(n)
        }

        part(1.2, 3.0, 1.4, limb, -0.8, 1.5, 0)                 // left leg
        part(1.2, 3.0, 1.4, limb,  0.8, 1.5, 0)                 // right leg
        part(3.2, 3.2, 1.8, bodyColor, 0, 4.6, 0)               // torso
        part(0.9, 2.8, 0.9, limb, -2.05, 4.6, 0)                // left arm
        part(0.9, 2.8, 0.9, limb,  2.05, 4.6, 0)                // right arm
        part(2.4, 2.2, 2.2, skin, 0, 7.4, 0, chamfer: 0.45)     // head
        part(2.7, 0.8, 2.7, bodyColor, 0, 8.7, 0, chamfer: 0.2) // cap

        // Status bulb + its own light, floating above the head.
        let bulb = SCNSphere(radius: 0.9)
        bulb.materials = [SCNMaterial()]
        let status = SCNNode(geometry: bulb)
        status.name = "status"
        status.position = SCNVector3(0, 10.6, 0)
        let sl = SCNLight(); sl.type = .omni; sl.attenuationEndDistance = 26
        status.light = sl
        figure.addChildNode(status)

        return root
    }

    /// Colors + animates a worker avatar for its current phase.
    static func applyPhase(_ phase: AgentWorker.Phase, to avatar: SCNNode) {
        guard let figure = avatar.childNodes.first else { return }

        let color: NSColor
        switch phase {
        case .working: color = NSColor.systemGreen
        case .waiting: color = NSColor.systemYellow
        case .done:    color = hex(0x38B2AC)
        case .failed:  color = NSColor.systemRed
        case .stopped: color = hex(0x8A8F98)
        }

        if let status = figure.childNode(withName: "status", recursively: false),
           let m = status.geometry?.firstMaterial {
            m.diffuse.contents = color
            m.emission.contents = color
            status.light?.color = color
            status.light?.intensity = (phase == .stopped) ? 0 : 340
            status.removeAllActions()
            status.scale = SCNVector3(1, 1, 1)
            switch phase {
            case .working:
                status.runAction(.repeatForever(.sequence([
                    .scale(to: 1.35, duration: 0.35), .scale(to: 1.0, duration: 0.35)])))
            case .waiting:
                status.runAction(.repeatForever(.sequence([
                    .scale(to: 1.25, duration: 1.0), .scale(to: 0.85, duration: 1.0)])))
            default:
                break
            }
        }

        // Body motion: bob while working, sway while waiting, rest otherwise.
        figure.removeAllActions()
        figure.position = SCNVector3Zero
        figure.eulerAngles = SCNVector3Zero
        switch phase {
        case .working:
            figure.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 1.1, z: 0, duration: 0.32),
                .moveBy(x: 0, y: -1.1, z: 0, duration: 0.32)])))
        case .waiting:
            figure.runAction(.repeatForever(.sequence([
                .rotateBy(x: 0, y: 0.22, z: 0, duration: 1.3),
                .rotateBy(x: 0, y: -0.22, z: 0, duration: 1.3)])))
        default:
            break
        }
    }

    // MARK: - Lighting + camera

    private static func addLighting(to root: SCNNode, style: Style) {
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = style.ambientIntensity
        ambient.light!.color = style.ambientColor
        root.addChildNode(ambient)

        let dir = SCNNode(); dir.light = SCNLight()
        dir.light!.type = .directional
        dir.light!.intensity = style.keyIntensity
        dir.light!.color = NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.9, alpha: 1)          // warm key
        dir.light!.castsShadow = true
        dir.light!.shadowColor = NSColor(white: 0, alpha: style.dark ? 0.5 : 0.28)                // softer shadows by day
        dir.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        root.addChildNode(dir)
    }

    private static func addCamera(to root: SCNNode, side: Float) {
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera!.zFar = 4000
        cam.camera!.fieldOfView = 50
        // Low, oblique angle so buildings read as a skyline rather than a flat map.
        cam.position = SCNVector3(side * 0.5, side * 0.5, side * 1.75)
        cam.look(at: SCNVector3(side / 2, side * 0.08, side / 2))
        root.addChildNode(cam)
    }
}
