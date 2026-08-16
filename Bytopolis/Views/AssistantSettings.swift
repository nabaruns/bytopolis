import SwiftUI

/// Provider configuration shown in a popover from the assistant pane's gear button.
struct AssistantSettings: View {
    @ObservedObject var assistant: AssistantModel
    @State private var keyField = ""
    @State private var hasKey = false

    private var provider: LLMProvider { assistant.provider }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assistant settings").font(.headline)

            Picker("Provider", selection: $assistant.provider) {
                ForEach(LLMProvider.allCases) { Text($0.label).tag($0) }
            }

            switch provider {
            case .anthropic:
                labeled("Model") { TextField("claude-sonnet-5", text: $assistant.anthropicModel) }
                keySection(hint: "console.anthropic.com", placeholder: "sk-ant-…")
            case .openAICompatible:
                labeled("Base URL") { TextField("https://openrouter.ai/api/v1", text: $assistant.openaiBaseURL) }
                labeled("Model") { TextField("openai/gpt-4o-mini", text: $assistant.openaiModel) }
                keySection(hint: "openrouter.ai/keys", placeholder: "sk-or-… / sk-…")
            case .localMLX:
                localSection
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { hasKey = Keychain.has(account: provider.keychainAccount) }
        .onChange(of: assistant.provider) { _, new in
            hasKey = Keychain.has(account: new.keychainAccount); keyField = ""
        }
    }

    private func labeled<V: View>(_ label: String, @ViewBuilder _ field: () -> V) -> some View {
        HStack {
            Text(label).frame(width: 72, alignment: .leading).foregroundStyle(.secondary)
            field().textFieldStyle(.roundedBorder).autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private func keySection(hint: String, placeholder: String) -> some View {
        Divider()
        if hasKey {
            HStack {
                Label("API key saved", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Spacer()
                Button("Change") { Keychain.delete(account: provider.keychainAccount); hasKey = false }
                    .buttonStyle(.link)
            }
        } else {
            Text("API key — stored in the macOS Keychain (\(hint)).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                SecureField(placeholder, text: $keyField).textFieldStyle(.roundedBorder)
                Button("Save") {
                    Keychain.set(keyField, account: provider.keychainAccount)
                    hasKey = Keychain.has(account: provider.keychainAccount); keyField = ""
                }
                .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var localSection: some View {
        Divider()
        Picker("Model", selection: $assistant.localModelID) {
            ForEach(LocalModelCatalog.models) { Text($0.name).tag($0.id) }
        }
        .pickerStyle(.menu)

        let model = LocalModelCatalog.model(assistant.localModelID)
        if LocalModelStore.isDownloaded(assistant.localModelID) {
            HStack {
                Label("Downloaded — runs offline", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Spacer()
                Button("Remove") { LocalModelStore.remove(assistant.localModelID); assistant.objectWillChange.send() }
                    .buttonStyle(.link)
            }
        } else if assistant.downloading {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: assistant.downloadProgress)
                Text("Downloading… \(Int(assistant.downloadProgress * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Button {
                assistant.downloadLocalModel()
            } label: {
                Label("Download \(model?.approxSize ?? "")", systemImage: "arrow.down.circle")
            }
        }

        if let e = assistant.downloadError {
            Text(e).font(.caption).foregroundStyle(.red)
        }
        Text("Runs fully offline on your Mac — nothing leaves the device. Apple Silicon required; first download is ~1–2 GB from Hugging Face.")
            .font(.caption).foregroundStyle(.secondary)
        if !MLXRunner.shared.isAvailable {
            Label("On-device runtime isn't built into this version yet.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}
