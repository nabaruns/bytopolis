import SwiftUI
import SceneKit
import AppKit
import Combine

/// The 3D "software city" view. Builds the layout off the main thread, renders it with
/// SceneKit, and shows an info panel for the clicked district/building/facility.
struct CityView: View {
    @ObservedObject var model: ScanModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var scene: SCNScene?
    @State private var layout: CityLayout?
    @State private var building = false
    @State private var selectedPath: String?

    // Workers (Phase 2)
    @StateObject private var workers = WorkerStore()
    @State private var configNode: CityNode?
    @State private var activeWorker: AgentWorker?
    @State private var avatars: [UUID: SCNNode] = [:]
    @State private var avatarPhase: [UUID: AgentWorker.Phase] = [:]
    @State private var tick = 0   // periodic nudge so time-based phases refresh the roster

    // Highlight of the selected node in the 3D scene
    @State private var highlightedNode: SCNNode?
    @State private var savedEmission: Any?

    private var selected: CityNode? {
        guard let p = selectedPath else { return nil }
        return layout?.nodes.first { $0.id == p }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let scene {
                SceneKitView(scene: scene) { name in
                    if name.hasPrefix("worker:") {
                        let uid = String(name.dropFirst("worker:".count))
                        if let w = workers.workers.first(where: { $0.id.uuidString == uid }) {
                            activeWorker = w
                            selectedPath = nil
                        }
                    } else {
                        selectedPath = name
                    }
                }
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
                if !workers.workers.isEmpty { workerRoster }
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
                    activeWorker = nil
                    syncAvatars()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(12)
            }
        }
        .task(id: buildKey) { await rebuild() }
        .onChange(of: colorScheme) { _, _ in restyle() }
        .onChange(of: selectedPath) { _, new in applyHighlight(new) }
        .onChange(of: workers.workers.count) { _, _ in syncAvatars() }
        .onReceive(Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()) { _ in
            if !workers.workers.isEmpty { tick &+= 1 }   // re-render roster
            syncAvatars()   // refresh working↔waiting and finished/stopped states over time
        }
        .sheet(item: $configNode) { node in
            WorkerConfigView(repoName: node.name, repoPath: node.id) { agent, mode, task in
                let worker = workers.start(repoPath: node.id, agent: agent, mode: mode, task: task)
                activeWorker = worker
                syncAvatars()
            }
        }
    }

    // MARK: - Worker avatars (a Lego-style figure per session, over its repo facility)

    /// Reconcile the scene's worker figures with the current worker set: add figures for new
    /// sessions, drop them when a session is removed, and restyle each to its live phase
    /// (working / waiting / done / failed / stopped). Multiple sessions on one repo are fanned
    /// out around the facility so they don't overlap.
    private func syncAvatars() {
        guard let scene, let layout else { return }
        let live = workers.workers
        let liveIDs = Set(live.map(\.id))

        for (id, node) in avatars where !liveIDs.contains(id) {
            node.removeFromParentNode()
            avatars[id] = nil
            avatarPhase[id] = nil
        }

        // Spots to fan out co-located sessions around a facility center.
        let ring: [(Float, Float)] = [(0, 0), (1, 1), (-1, 1), (1, -1), (-1, -1), (0, 1.5), (0, -1.5)]
        var perRepo: [String: Int] = [:]

        for w in live {
            guard let facility = layout.nodes.first(where: { $0.id == w.repoPath }) else { continue }
            let idx = perRepo[w.repoPath, default: 0]; perRepo[w.repoPath] = idx + 1

            let node: SCNNode
            if let existing = avatars[w.id] {
                node = existing
            } else {
                let n = CityScene.makeWorkerAvatar(agent: w.agent, id: w.id)
                let spread = Float(min(facility.rect.width, facility.rect.height)) * 0.22
                let off = ring[min(idx, ring.count - 1)]
                let baseY = Float(facility.depth) * 1.4 + 0.6
                n.position = SCNVector3(Float(facility.rect.midX) + off.0 * spread,
                                        baseY,
                                        Float(facility.rect.midY) + off.1 * spread)
                scene.rootNode.addChildNode(n)
                avatars[w.id] = n
                node = n
            }

            let p = w.phase
            if avatarPhase[w.id] != p {
                CityScene.applyPhase(p, to: node)
                avatarPhase[w.id] = p
            }
        }
    }

    // MARK: - Build

    /// Rebuild when the path changes OR when the scan/index finishes (so the city uses the
    /// cached index instead of an empty snapshot taken before the scan completed).
    private var buildKey: String {
        "\(model.targetPath)#\(model.indexBuiltAt?.timeIntervalSinceReferenceDate ?? 0)"
    }

    private func rebuild() async {
        // Wait for a chosen workspace — an empty target standardizes to the cwd ("/").
        let raw = model.targetPath.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { scene = nil; layout = nil; building = false; return }
        let root = DiskScanner.standardize(raw)

        // Index not ready yet (scan still running) — show the spinner; this task re-fires
        // via `buildKey` once `indexBuiltAt` updates.
        guard model.currentIndex != nil else { building = true; scene = nil; layout = nil; return }
        building = true
        selectedPath = nil
        let idx = model.currentIndex
        let built = await Task.detached(priority: .userInitiated) {
            CityModel.build(root: root, index: idx, now: Date())
        }.value
        layout = built
        highlightedNode = nil; savedEmission = nil     // old scene's nodes are gone
        avatars = [:]; avatarPhase = [:]               // avatars belonged to the old scene
        scene = CityScene.make(from: built, dark: colorScheme == .dark)   // fast; nodes only
        building = false
        syncAvatars()                                  // re-place any live worker figures
    }

    /// Rebuild just the scene (not the layout) when the system switches light/dark, so the
    /// city repaints for the new appearance. Cheap — geometry only.
    private func restyle() {
        guard let layout else { return }
        highlightedNode = nil; savedEmission = nil
        avatars = [:]; avatarPhase = [:]
        scene = CityScene.make(from: layout, dark: colorScheme == .dark)
        syncAvatars()
    }

    /// Glow the node matching `path` in the scene (and clear the previous one), so clicking
    /// a side-list row — or a tile — lights it up on the map.
    private func applyHighlight(_ path: String?) {
        if let prev = highlightedNode {
            prev.geometry?.firstMaterial?.emission.contents = savedEmission
        }
        highlightedNode = nil; savedEmission = nil
        guard let path, let node = scene?.rootNode.childNode(withName: path, recursively: true),
              let material = node.geometry?.firstMaterial else { return }
        savedEmission = material.emission.contents
        material.emission.contents = NSColor.white
        highlightedNode = node
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

    /// Live roster of worker sessions with a colored status dot — click a row to open its
    /// session. Mirrors the 3D figures in the city (same statuses, same colors).
    private var workerRoster: some View {
        let _ = tick   // participate in the periodic refresh
        return VStack(alignment: .leading, spacing: 0) {
            Text("Workers").font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(workers.workers) { w in
                    Button { activeWorker = w } label: {
                        WorkerRosterRow(worker: w)
                            .background(activeWorker?.id == w.id ? Color.accentColor.opacity(0.22) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4).padding(.bottom, 6)
        }
        .frame(width: 236)
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

/// One row in the worker roster: a phase-colored dot, the agent, the repo, and a status
/// line. Observes the worker so status/output changes refresh it live.
private struct WorkerRosterRow: View {
    @ObservedObject var worker: AgentWorker

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(phaseColor).frame(width: 9, height: 9)
                .shadow(color: phaseColor.opacity(0.8), radius: worker.phase == .working ? 3 : 0)
            Image(systemName: worker.agent == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right")
                .font(.caption2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(worker.repoName).font(.caption).lineLimit(1)
                Text(phaseLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 3).padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var phaseColor: Color {
        switch worker.phase {
        case .working: return .green
        case .waiting: return .yellow
        case .done:    return .teal
        case .failed:  return .red
        case .stopped: return .gray
        }
    }
    private var phaseLabel: String {
        switch worker.phase {
        case .working: return "working…"
        case .waiting: return "waiting for response…"
        case .done:    return worker.changesSummary ?? "done"
        case .failed:  return "failed"
        case .stopped: return "stopped"
        }
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
        view.backgroundColor = .windowBackgroundColor   // adapts to light/dark behind the scene
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
