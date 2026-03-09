import SwiftUI
import Carbon

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var endpoint:    String = ""
    @State private var apiKey:      String = ""
    @State private var selected:    String = ""
    @State private var isFetching:  Bool   = false
    @State private var fetchError:  String?

    // Hotkey
    @State private var hotkeyKeyCode:    UInt32 = 49
    @State private var hotkeyModifiers:  UInt32 = 6144
    @State private var hotkeyDisplay:    String = "⌃⌥Space"
    @State private var isRecording:      Bool   = false
    @State private var eventMonitor:     Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Done") { saveAndDismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // API Endpoint
                    section("API Endpoint") {
                        TextField("https://api.openai.com/v1", text: $endpoint)
                            .textFieldStyle(.roundedBorder)
                    }

                    // API Key
                    section("API Key") {
                        SecureField("sk-…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Refresh models
                    HStack {
                        Button(action: refreshModels) {
                            HStack(spacing: 6) {
                                if isFetching { ProgressView().scaleEffect(0.7) }
                                Text(isFetching ? "Fetching…" : "Refresh Models")
                            }
                        }
                        .disabled(isFetching || endpoint.isEmpty || apiKey.isEmpty)

                        if let err = fetchError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }
                    }

                    Divider()

                    // Model picker
                    section("Model") {
                        if appState.availableModels.isEmpty {
                            Text("No models loaded — enter credentials and tap Refresh Models.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Picker("", selection: $selected) {
                                ForEach(appState.availableModels, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    Divider()

                    // Global hotkey
                    section("Global Shortcut") {
                        HStack(spacing: 10) {
                            // Pill showing current shortcut
                            Text(isRecording ? "Press shortcut…" : hotkeyDisplay)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    isRecording
                                        ? Color.accentColor.opacity(0.12)
                                        : Color(NSColor.controlBackgroundColor)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            isRecording ? Color.accentColor : Color.secondary.opacity(0.3),
                                            lineWidth: 1
                                        )
                                )

                            Button(isRecording ? "Cancel" : "Record") {
                                isRecording ? stopRecording() : startRecording()
                            }
                            .buttonStyle(.bordered)
                        }
                        Text("Shown in menu bar and triggered globally.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420)
        .onAppear {
            endpoint        = appState.settings.apiEndpoint
            apiKey          = appState.settings.apiKey
            selected        = appState.settings.selectedModel
            hotkeyKeyCode   = appState.settings.hotkeyKeyCode
            hotkeyModifiers = appState.settings.hotkeyModifiers
            hotkeyDisplay   = appState.settings.hotkeyDisplayName
        }
        .onDisappear { stopRecording() }
    }

    // MARK: - Hotkey recording

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            // Require at least one modifier
            let mods = event.modifierFlags.carbonModifiers
            guard mods != 0 else { return event }

            hotkeyKeyCode   = UInt32(event.keyCode)
            hotkeyModifiers = mods
            hotkeyDisplay   = event.shortcutDisplayString
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // MARK: - Actions

    private func refreshModels() {
        appState.settings.apiEndpoint = endpoint
        appState.settings.apiKey      = apiKey
        isFetching = true
        fetchError = nil
        Task {
            await appState.fetchModels()
            isFetching = false
            if let err = appState.setupError {
                fetchError = err
            } else {
                selected = appState.settings.selectedModel
            }
        }
    }

    private func saveAndDismiss() {
        appState.settings.apiEndpoint       = endpoint
        appState.settings.apiKey            = apiKey
        appState.settings.selectedModel     = selected
        appState.settings.hotkeyKeyCode     = hotkeyKeyCode
        appState.settings.hotkeyModifiers   = hotkeyModifiers
        appState.settings.hotkeyDisplayName = hotkeyDisplay
        appState.saveData()
        dismiss()
    }

    // MARK: - Helper

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

// MARK: - NSEvent helpers

private extension NSEvent.ModifierFlags {
    /// Convert NSEvent modifier flags to Carbon modifier flags
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.option)  { result |= UInt32(optionKey) }
        if contains(.shift)   { result |= UInt32(shiftKey) }
        if contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

private extension NSEvent {
    /// Human-readable shortcut string, e.g. "⌃⌥Space"
    var shortcutDisplayString: String {
        var s = ""
        if modifierFlags.contains(.control) { s += "⌃" }
        if modifierFlags.contains(.option)  { s += "⌥" }
        if modifierFlags.contains(.shift)   { s += "⇧" }
        if modifierFlags.contains(.command) { s += "⌘" }

        switch Int(keyCode) {
        case kVK_Space:      s += "Space"
        case kVK_Return:     s += "Return"
        case kVK_Tab:        s += "Tab"
        case kVK_Delete:     s += "Delete"
        case kVK_UpArrow:    s += "↑"
        case kVK_DownArrow:  s += "↓"
        case kVK_LeftArrow:  s += "←"
        case kVK_RightArrow: s += "→"
        default:
            s += (charactersIgnoringModifiers ?? "?").uppercased()
        }
        return s
    }
}
