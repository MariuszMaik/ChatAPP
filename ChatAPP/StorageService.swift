import Foundation
import CryptoKit
import Security

/// All sensitive data goes through this service.
///
/// Security model:
/// - AES-256-GCM encryption for files on disk (conversations, settings)
/// - The AES encryption key lives in Keychain (ThisDeviceOnly, never syncs)
/// - The API key lives DIRECTLY in Keychain (ThisDeviceOnly, never in any file)
/// - Conversation history is encrypted with AES-256-GCM — authenticated encryption
///   provides both confidentiality and integrity guarantees
final class StorageService {
    static let shared = StorageService()
    private init() {}

    // MARK: - Keychain accounts

    private let encKeyAccount  = "com.chatapp.encryptionKey"
    private let apiKeyAccount  = "com.chatapp.apiKey"

    // MARK: - File names (on disk, encrypted)

    private let conversationsFile = "conversations.enc"
    private let settingsFile      = "settings.enc"

    // MARK: - AES-256-GCM encryption key (Keychain, ThisDeviceOnly)

    private lazy var encryptionKey: SymmetricKey = { loadOrCreateEncKey() }()

    private func loadOrCreateEncKey() -> SymmetricKey {
        if let data = keychainLoad(account: encKeyAccount) {
            return SymmetricKey(data: data)
        }
        let key     = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        keychainSave(data: keyData, account: encKeyAccount)
        return key
    }

    // MARK: - Generic Keychain helpers (ThisDeviceOnly — no iCloud sync)

    private func keychainSave(data: Data, account: String) {
        let base: [String: Any] = [
            kSecClass as String:      kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        // Update if exists, otherwise add
        if SecItemUpdate(base as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var addQuery = base
            addQuery.merge(attrs) { _, new in new }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func keychainLoad(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - API Key (Keychain only — never written to any file)

    func saveAPIKey(_ key: String) {
        if key.isEmpty {
            keychainDelete(account: apiKeyAccount)
        } else {
            keychainSave(data: Data(key.utf8), account: apiKeyAccount)
        }
    }

    func loadAPIKey() -> String {
        guard let data = keychainLoad(account: apiKeyAccount),
              let key  = String(data: data, encoding: .utf8)
        else { return "" }
        return key
    }

    // MARK: - AES-256-GCM encrypt / decrypt

    private func encrypt<T: Encodable>(_ value: T) throws -> Data {
        let plain    = try JSONEncoder().encode(value)
        let sealBox  = try AES.GCM.seal(plain, using: encryptionKey)
        guard let combined = sealBox.combined else { throw CocoaError(.fileWriteUnknown) }
        return combined
    }

    private func decrypt<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let sealBox   = try AES.GCM.SealedBox(combined: data)
        let plain     = try AES.GCM.open(sealBox, using: encryptionKey)
        return try JSONDecoder().decode(type, from: plain)
    }

    // MARK: - File URLs (Application Support / ChatAPP)

    private func fileURL(for name: String) -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatAPP")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    // MARK: - Conversations (AES-256-GCM encrypted file)

    func saveConversations(_ conversations: [Conversation]) {
        guard let data = try? encrypt(conversations) else { return }
        try? data.write(to: fileURL(for: conversationsFile), options: .atomic)
    }

    func loadConversations() -> [Conversation] {
        guard
            let data   = try? Data(contentsOf: fileURL(for: conversationsFile)),
            let result = try? decrypt(data, as: [Conversation].self)
        else { return [] }
        return result
    }

    // MARK: - Settings (AES-256-GCM encrypted file — apiKey excluded)

    func saveSettings(_ settings: AppSettings) {
        guard let data = try? encrypt(settings) else { return }
        try? data.write(to: fileURL(for: settingsFile), options: .atomic)
    }

    func loadSettings() -> AppSettings {
        guard
            let data   = try? Data(contentsOf: fileURL(for: settingsFile)),
            let result = try? decrypt(data, as: AppSettings.self)
        else { return AppSettings() }
        return result
    }
}
