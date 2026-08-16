import SceneKit
import AppKit

/// Builds an SCNScene from a `CityLayout`: districts as raised plots, files as buildings
/// sized by bytes, git repos as walled facilities, recent items glowing, and a beacon over
/// the single most-recently-modified "entry". Each node carries its path in `name` for
/// hit-testing.
enum CityScene {
    static func make(from layout: CityLayout) -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode
        let side = CGFloat(layout.bounds.width)

        // Ground.
        let floor = SCNBox(width: side + 10, height: 1, length: side + 10, chamferRadius: 0)
        floor.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.14, alpha: 1)
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

            case .building:
                let h = CGFloat(max(0.6, n.height))
                let inset = min(w, l) * 0.14
                let box = SCNBox(width: max(0.4, w - inset), height: h,
                                 length: max(0.4, l - inset), chamferRadius: 0)
                let mat = SCNMaterial()
                mat.diffuse.contents = buildingColor(n)
                if n.isRecent { mat.emission.contents = glowColor(n) }
                box.materials = [mat]
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(cx, baseY + 0.6 + Float(h) / 2, cz)
                node.name = n.id
                root.addChildNode(node)
                if n.isEntry { addBeacon(to: root, x: cx, y: baseY + 0.6 + Float(h) + 5, z: cz) }
            }
        }

        addLighting(to: root)
        addCamera(to: root, side: Float(side))
        scene.background.contents = NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1)
        return scene
    }

    // MARK: - Colors

    private static func base(_ cat: ReclaimCategory?) -> NSColor {
        switch cat?.reclaim ?? .keep {
        case .keep:    return NSColor(calibratedHue: 0.58, saturation: 0.22, brightness: 0.78, alpha: 1)
        case .caution: return NSColor(calibratedHue: 0.08, saturation: 0.70, brightness: 0.92, alpha: 1)
        case .safe:    return NSColor(calibratedHue: 0.38, saturation: 0.60, brightness: 0.85, alpha: 1)
        }
    }

    private static func buildingColor(_ n: CityNode) -> NSColor {
        // Reclaimable files use the category color; everything else gets a stable,
        // muted hue from its file extension so the skyline is varied, not all grey.
        if let c = n.category, c.reclaim != .keep { return base(c) }
        let ext = (n.name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return NSColor(calibratedWhite: 0.72, alpha: 1) }
        let seed = ext.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        let hue = Double(seed % 360) / 360.0
        return NSColor(calibratedHue: CGFloat(hue), saturation: 0.38, brightness: 0.78, alpha: 1)
    }

    private static func glowColor(_ n: CityNode) -> NSColor {
        base(n.category).blended(withFraction: 0.5, of: .white) ?? .white
    }

    private static func plotColor(_ n: CityNode) -> NSColor {
        if n.kind == .facility {
            return NSColor(calibratedHue: 0.75, saturation: 0.45, brightness: 0.5, alpha: 1)
        }
        let shade = 0.13 + Double(n.depth % 3) * 0.04
        return NSColor(calibratedWhite: shade, alpha: 1)
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
        ambient.light!.intensity = 350
        ambient.light!.color = NSColor(calibratedWhite: 0.7, alpha: 1)
        root.addChildNode(ambient)

        let dir = SCNNode(); dir.light = SCNLight()
        dir.light!.type = .directional
        dir.light!.intensity = 900
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
