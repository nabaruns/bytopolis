import SwiftUI
import SceneKit
import AppKit

/// The 3D "software city" view. Builds the layout off the main thread, renders it with
/// SceneKit, and shows an info panel for the clicked district/building/facility.
struct CityView: View {
    @ObservedObject var model: ScanModel

    @State private var scene: SCNScene?
    @State private var layout: CityLayout?
    @State private var building = false
    @State private var selectedPath: String?

    // Workers (Phase 2)
    @StateObject private var workers = WorkerStore()
    @State private var configNode: CityNode?
    @State private var activeWorker: AgentWorker?
    @State private var avatars: [UUID: SCNNode] = [:]

    private var selected: CityNode? {
        guard let p = selectedPath else { return nil }
        return layout?.nodes.first { $0.id == p }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let scene {
                SceneKitView(scene: scene) { selectedPath = $0 }
            } else {
                Color(nsColor: .textBackgroundColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                legend
                if layout?.truncated == true {
                    Label("Large tree — city truncated for performance", systemImage: "scissors")
                        .font(.caption).padding(6)
                        .background(.thinMaterial, in: Capsule())
                }
                sideList
            }
            .padding(10)

            if building {
                ProgressView("Building city…")
                    .padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let node = selected, activeWorker == nil {
                infoPanel(node)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
            }

            if let worker = activeWorker {
                WorkerPanel(worker: worker) {
                    workers.remove(worker)
                    removeAvatar(worker.id)
                    activeWorker = nil
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(12)
            }
        }
        .task(id: model.targetPath) { await rebuild() }
        .sheet(item: $configNode) { node in
            WorkerConfigView(repoName: node.name, repoPath: node.id) { agent, mode, task in
                let worker = workers.start(repoPath: node.id, agent: agent, mode: mode, task: task)
                activeWorker = worker
                addAvatar(for: node, worker: worker)
            }
        }
    }

    // MARK: - Worker avatars (a bobbing marker over an active repo facility)

    private func addAvatar(for node: CityNode, worker: AgentWorker) {
        guard let scene else { return }
        let sphere = SCNSphere(radius: 2)
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor.systemOrange
        mat.emission.contents = NSColor.systemOrange
        sphere.materials = [mat]
        let avatar = SCNNode(geometry: sphere)
        avatar.name = node.id
        let baseY = Float(node.depth) * 1.4
        avatar.position = SCNVector3(Float(node.rect.midX), baseY + 11, Float(node.rect.midY))
        let light = SCNLight(); light.type = .omni; light.color = NSColor.systemOrange; light.intensity = 500
        avatar.light = light
        avatar.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 2.5, z: 0, duration: 0.7),
            .moveBy(x: 0, y: -2.5, z: 0, duration: 0.7)
        ])))
        scene.rootNode.addChildNode(avatar)
        avatars[worker.id] = avatar
    }

    private func removeAvatar(_ id: UUID) {
        avatars[id]?.removeFromParentNode()
        avatars[id] = nil
    }

    // MARK: - Build

    private func rebuild() async {
        // Wait for a chosen workspace — an empty target standardizes to the cwd ("/").
        let raw = model.targetPath.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { scene = nil; layout = nil; building = false; return }
        let root = DiskScanner.standardize(raw)
        building = true
        selectedPath = nil
        let idx = model.currentIndex
        let built = await Task.detached(priority: .userInitiated) {
            CityModel.build(root: root, index: idx, now: Date())
        }.value
        layout = built
        scene = CityScene.make(from: built)   // fast; nodes only
        building = false
    }

    // MARK: - Overlays

    private var legend: some View {
        HStack(spacing: 10) {
            swatch(.green, "safe"); swatch(.orange, "caution")
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [.blue, .teal, .purple, .pink], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 12, height: 10)
                Text("by type")
            }
            HStack(spacing: 4) { Circle().fill(.yellow).frame(width: 9, height: 9); Text("newest") }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.49, green: 0.36, blue: 0.84)).frame(width: 10, height: 10)
                Text("repo")
            }
        }
        .font(.caption2)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }

    /// The current level's neighborhoods listed on the side — names live here instead of
    /// floating over the 3D city (which overlapped). Click a row to select it in the scene.
    private var sideList: some View {
        let items = (layout?.nodes.filter { $0.depth == 0 } ?? []).sorted { $0.byteSize > $1.byteSize }
        return VStack(alignment: .leading, spacing: 0) {
            Text("This level").font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(items) { n in
                        Button { selectedPath = n.id } label: {
                            HStack(spacing: 6) {
                                if n.kind == .facility {
                                    Image(systemName: "shippingbox.fill").font(.caption2)
                                        .foregroundStyle(Color(red: 0.49, green: 0.36, blue: 0.84))
                                } else {
                                    Circle().fill(color(for: n)).frame(width: 8, height: 8)
                                }
                                Text(n.name).font(.caption).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(ByteCountFormatter.string(fromByteCount: n.byteSize, countStyle: .file))
                                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .padding(.vertical, 3).padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedPath == n.id ? Color.accentColor.opacity(0.25) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4).padding(.bottom, 6)
            }
        }
        .frame(width: 236)
        .frame(maxHeight: 360)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    private func swatch(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(label)
        }
    }

    private func infoPanel(_ node: CityNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon(for: node)).foregroundStyle(color(for: node))
                Text(node.name).font(.headline).lineLimit(1)
                Spacer()
                Button { selectedPath = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            Text(node.id).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 10) {
                Text(ByteCountFormatter.string(fromByteCount: node.byteSize, countStyle: .file)).bold()
                if let c = node.category, c.reclaim != .keep {
                    Text(c.name).font(.caption).foregroundStyle(c.reclaim.color)
                }
                if let m = node.mtime {
                    Text(m.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
            }

            if let git = node.git {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    Text(git.branch ?? "—").font(.callout)
                    if git.isGitHub {
                        Text("GitHub").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if let url = git.remoteURL {
                    Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Button {
                    configNode = node
                } label: {
                    Label(workers.running(forRepo: node.id) ? "Worker running…" : "Start worker",
                          systemImage: "person.fill.badge.plus")
                }
                .help("Attach a Claude/Codex session to this repo (headless)")
            }

            HStack {
                if node.kind != .building {
                    Button("Open") { model.targetPath = node.id; model.scan() }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.id)])
                }
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))          // opaque → reliable contrast
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        )
        .shadow(radius: 12)
    }

    private func icon(for node: CityNode) -> String {
        switch node.kind {
        case .facility: return "shippingbox.fill"
        case .district: return "folder.fill"
        case .building: return "building.2.fill"
        }
    }
    private func color(for node: CityNode) -> Color {
        node.kind == .facility
            ? Color(hue: 0.75, saturation: 0.5, brightness: 0.7)
            : (node.category?.reclaim ?? .keep).color
    }
}

/// SwiftUI wrapper around SCNView with camera control + click hit-testing.
private struct SceneKitView: NSViewRepresentable {
    let scene: SCNScene
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .black
        let click = NSClickGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleClick(_:)))
        view.addGestureRecognizer(click)
        context.coordinator.view = view
        view.scene = scene
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.onSelect = onSelect
        if view.scene !== scene { view.scene = scene }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject {
        weak var view: SCNView?
        var onSelect: (String) -> Void
        init(onSelect: @escaping (String) -> Void) { self.onSelect = onSelect }

        @objc func handleClick(_ g: NSClickGestureRecognizer) {
            guard let view else { return }
            let p = g.location(in: view)
            let hits = view.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            if let name = hits.first?.node.name ?? hits.first?.node.parent?.name {
                onSelect(name)
            }
        }
    }
}
