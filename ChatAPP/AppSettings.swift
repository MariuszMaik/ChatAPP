import Foundation

struct AppSettings: Codable {
    var apiEndpoint: String = "https://api.openai.com/v1"
    var selectedModel: String = ""
    var availableModels: [String] = []

    // Global hotkey — stored as Carbon modifier flags + virtual key code
    var hotkeyKeyCode: UInt32 = 49      // kVK_Space
    var hotkeyModifiers: UInt32 = 6144  // controlKey | optionKey
    var hotkeyDisplayName: String = "⌃⌥Space"

    // API key is intentionally NOT in Codable — it lives in Keychain only.
    // Kept as a transient in-memory field so the rest of the app can read it.
    var apiKey: String = ""

    enum CodingKeys: String, CodingKey {
        case apiEndpoint, selectedModel, availableModels
        case hotkeyKeyCode, hotkeyModifiers, hotkeyDisplayName
        // apiKey is deliberately omitted
    }

    var isConfigured: Bool {
        !apiEndpoint.isEmpty && !apiKey.isEmpty && !selectedModel.isEmpty
    }
}
