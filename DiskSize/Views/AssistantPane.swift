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
        .padding(.horizontal, 10)
        .frame(height: 44)
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
                VStack(alignment: .leading, spacing: 4) {
                    if message.text.isEmpty && assistant.streaming {
                        TypingIndicator()
                    } else {
                        MarkdownText(text: message.text).textSelection(.enabled)
                        if !message.text.isEmpty {
                            HStack(spacing: 10) {
                                CopyButton(text: message.text)
                                if assistant.streaming && message.id == assistant.messages.last?.id {
                                    Label("Generating…", systemImage: "ellipsis")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if assistant.warming {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading local model…").foregroundStyle(.secondary).font(.callout)
                }
            }
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
                .disabled(!assistant.isReady || assistant.streaming)
            if assistant.streaming {
                Button { assistant.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.title2).foregroundStyle(.red)
                }
                .buttonStyle(.borderless).help("Stop")
            } else {
                Button { assistant.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.borderless)
                    .disabled(!assistant.isReady
                              || assistant.input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8)
    }
}

/// Animated three-dot "typing" indicator shown while the first tokens are pending.
private struct TypingIndicator: View {
    @State private var animating = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(animating ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2),
                               value: animating)
            }
            Text("Generating…").font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
        }
        .onAppear { animating = true }
    }
}

/// A copy-to-clipboard button that briefly confirms.
private struct CopyButton: View {
    let text: String
    @State private var copied = false
    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            Label(copied ? "Copied" : "Copy",
                  systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(copied ? .green : .secondary)
    }
}
