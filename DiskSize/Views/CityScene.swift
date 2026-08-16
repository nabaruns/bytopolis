import SceneKit
import AppKit

/// Builds an SCNScene from a `CityLayout`: districts as raised plots, files as buildings
/// sized by bytes, git repos as walled facilities, recent items glowing, and a beacon over
/// the single most-recently-modified "entry". Each node carries its path in `name` for
/// hit-testing.
enum CityScene {
    static let maxLabels = 90

    static func make(from layout: CityLayout) -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode
        let side = CGFloat(layout.bounds.width)
        var labelCount = 0

        // Ground.
        let floor = SCNBox(width: side + 10, height: 1, length: side + 10, chamferRadius: 0)
        floor.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.15, alpha: 1)
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
                box.firstMaterial?.diffuse.contents = plotColor(n)
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(cx, baseY + Float(plotH / 2), cz)
                node.name = n.id
                root.addChildNode(node)
                if n.kind == .facility { addWalls(to: root, rect: n.rect, baseY: baseY + Float(plotH)) }
                // Label only the current level's neighborhoods; drill in to see deeper names.
                if n.depth == 0, min(w, l) > 8, labelCount < maxLabels {
                    addLabel(n.name, id: n.id, to: root,
                             at: SCNVector3(cx, baseY + Float(plotH) + 6, cz), color: .white)
                    labelCount += 1
                }

            case .building:
                let h = CGFloat(max(0.6, n.height))
                let inset = min(w, l) * 0.14
                let box = SCNBox(width: max(0.4, w - inset), height: h,
                                 length: max(0.4, l - inset), chamferRadius: 0)
                let mat = SCNMaterial()
                mat.diffuse.contents = buildingColor(n)
                mat.emission.contents = n.isRecent ? glowColor(n) : emissionColor(n)
                box.materials = [mat]
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(cx, baseY + 0.6 + Float(h) / 2, cz)
                node.name = n.id
                root.addChildNode(node)
                let topY = baseY + 0.6 + Float(h)
                if n.isEntry { addBeacon(to: root, x: cx, y: topY + 5, z: cz) }
                if n.depth == 0, min(w, l) > 8, labelCount < maxLabels {
                    addLabel(n.name, id: n.id, to: root,
                             at: SCNVector3(cx, topY + 2.5, cz), color: .white)
                    labelCount += 1
                }
            }
        }

        addLighting(to: root)
        addCamera(to: root, side: Float(side))
        scene.background.contents = NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1)
        return scene
    }

    // MARK: - Colors

    private static func hex(_ v: Int) -> NSColor {
        NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Curated palette for file "buildings" (picked by extension) — vivid but cohesive.
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

    private static func glowColor(_ n: CityNode) -> NSColor {
        buildingColor(n).blended(withFraction: 0.55, of: .white) ?? .white
    }

    /// Subtle self-illumination so buildings read as a lit night city.
    private static func emissionColor(_ n: CityNode) -> NSColor {
        buildingColor(n).blended(withFraction: 0.8, of: .black) ?? .black
    }

    private static func plotColor(_ n: CityNode) -> NSColor {
        if n.kind == .facility {
            return hex(0x7C5CD6)   // violet plot for repos
        }
        // Cool slate districts, lightening a touch with depth.
        let base = 0.17 + Double(n.depth % 3) * 0.05
        return NSColor(calibratedRed: base * 0.9, green: base, blue: base * 1.25, alpha: 1)
    }

    // MARK: - Facility walls + beacon

    private static func addWalls(to root: SCNNode, rect: CGRect, baseY: Float) {
        let t: CGFloat = 0.7, hWall: CGFloat = 3
        let color = NSColor(calibratedHue: 0.75, saturation: 0.5, brightness: 0.7, alpha: 1)
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

    /// A billboarded name tag above a node. Carries the node's path in `name` so a click
    /// on the label selects the same node. Kept to the larger nodes (and capped) to avoid
    /// clutter and geometry cost.
    private static func addLabel(_ text: String, id: String, to root: SCNNode,
                                 at pos: SCNVector3, color: NSColor) {
        let scnText = SCNText(string: String(text.prefix(22)), extrusionDepth: 0)
        scnText.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        scnText.flatness = 0.4
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color        // self-lit so it reads on any building
        mat.isDoubleSided = true
        scnText.materials = [mat]

        let node = SCNNode(geometry: scnText)
        let (minB, maxB) = scnText.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2,
                                               (minB.y + maxB.y) / 2,
                                               (minB.z + maxB.z) / 2)
        let s: Float = 0.5
        node.scale = SCNVector3(s, s, s)
        node.position = pos
        node.name = id
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y              // stay upright, turn to face the camera
        node.constraints = [billboard]
        root.addChildNode(node)
    }

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

    // MARK: - Lighting + camera

    private static func addLighting(to root: SCNNode) {
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 550
        ambient.light!.color = NSColor(calibratedRed: 0.62, green: 0.66, blue: 0.78, alpha: 1)  // cool fill
        root.addChildNode(ambient)

        let dir = SCNNode(); dir.light = SCNLight()
        dir.light!.type = .directional
        dir.light!.intensity = 1100
        dir.light!.color = NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.9, alpha: 1)          // warm key
        dir.light!.castsShadow = true
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
