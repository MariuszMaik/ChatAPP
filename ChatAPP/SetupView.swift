import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appState: AppState

    @State private var endpoint: String = "https://api.openai.com/v1"
    @State private var apiKey:   String = ""
    @State private var selected: String = ""
    @State private var step: Step = .credentials

    enum Step { case credentials, modelPicker }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if step == .credentials { credentialsForm }
                else                    { modelPicker }
            }
            .padding(24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
            Text("ChatAPP")
                .font(.largeTitle).fontWeight(.bold)
            Text("Connect your OpenAI-compatible API to get started")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 28)
        .padding(.bottom, 20)
        .padding(.horizontal, 24)
    }

    // MARK: - Step 1: credentials

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            labeled("API Endpoint") {
                TextField("https://api.openai.com/v1", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
            }
            labeled("API Key") {
                SecureField("sk-…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            if let err = appState.setupError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(action: fetchModels) {
                HStack {
                    if appState.isLoadingModels { ProgressView().scaleEffect(0.75) }
                    Text(appState.isLoadingModels ? "Connecting…" : "Connect & Fetch Models")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(endpoint.isEmpty || apiKey.isEmpty || appState.isLoadingModels)
        }
    }

    // MARK: - Step 2: model selection

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a model")
                .font(.headline)
            Text("\(appState.availableModels.count) models found — pick one for all conversations.")
                .font(.subheadline).foregroundColor(.secondary)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(appState.availableModels, id: \.self) { model in
                        modelRow(model)
                    }
                }
            }
            .frame(maxHeight: 280)

            Button(action: finish) {
                Text("Start Chatting →")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
    }

    private func modelRow(_ model: String) -> some View {
        HStack {
            Image(systemName: selected == model ? "checkmark.circle.fill" : "circle")
                .foregroundColor(selected == model ? .accentColor : .secondary)
            Text(model)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected == model ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { selected = model }
    }

    // MARK: - Actions

    private func fetchModels() {
        appState.settings.apiEndpoint = endpoint
        appState.settings.apiKey      = apiKey
        Task {
            await appState.fetchModels()
            if appState.setupError == nil {
                selected = appState.availableModels.first ?? ""
                step = .modelPicker
            }
        }
    }

    private func finish() {
        appState.settings.selectedModel = selected
        appState.completeSetup()
        appState.startNewConversation()
    }

    // MARK: - Helper

    private func labeled<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            content()
        }
    }
}
