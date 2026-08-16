import SwiftUI

/// The right-hand assistant chat pane: a running transcript with Markdown-rendered
/// answers, quick prompts, an input bar, and a settings popover.
struct AssistantPane: View {
    @ObservedObject var assistant: AssistantModel
    var onClose: () -> Void
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            inputBar
        }
        .frame(minWidth: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Assistant", systemImage: "wand.and.stars").font(.headline)
            Spacer()
            if !assistant.messages.isEmpty {
                Button { assistant.clear() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Clear conversation")
            }
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    AssistantSettings(assistant: assistant)
                }
            Button { onClose() } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(.borderless).help("Hide assistant")
        }
        .padding(8)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if assistant.messages.isEmpty { emptyState }
                    ForEach(assistant.messages) { message in
                        bubble(for: message).id(message.id)
                    }
                    if let e = assistant.errorText {
                        Text(e).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .padding(10)
            }
            .onChange(of: assistant.messages.last?.text) {
                if let last = assistant.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder
    private func bubble(for message: AssistantModel.Message) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 32)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.secondary).padding(.top, 2)
                if message.text.isEmpty && assistant.streaming {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(.secondary) }
                } else {
                    MarkdownText(text: message.text).textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !assistant.isReady {
                Label("Set up a provider to start", systemImage: "gearshape")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open settings") { showSettings = true }.buttonStyle(.borderless)
            } else {
                Text("Ask about what to clean up:").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(assistant.quickPrompts, id: \.self) { p in
                Button { assistant.send(p) } label: {
                    Text(p).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(assistant.streaming || !assistant.isReady)
            }
        }
        .padding(.bottom, 4)
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            TextField("Ask…", text: $assistant.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { assistant.send() }
                .disabled(!assistant.isReady)
            Button { assistant.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .buttonStyle(.borderless)
                .disabled(assistant.streaming || !assistant.isReady
                          || assistant.input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
    }
}
