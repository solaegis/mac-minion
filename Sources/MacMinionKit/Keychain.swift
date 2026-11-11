import Foundation
import Security

/// API keys live in the user's login Keychain, one item per provider, readable only while the Mac is
/// unlocked. Never in UserDefaults, state.json, logs, or error messages.
public struct KeychainStore: Sendable {
    /// Namespaced by bundle ID: com.solaegis.macminion.
    public let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.solaegis.macminion") {
        self.service = service
    }

    /// "claude-api-key" is the name MacMinion has always used, so saved Claude keys carry over.
    public static func account(for provider: AIProvider) -> String {
        "\(provider.rawValue)-api-key"
    }

    public func key(for provider: AIProvider) -> String? {
        var query = base(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Saves or replaces the key. An empty key removes it.
    @discardableResult
    public func save(_ key: String, for provider: AIProvider) -> Bool {
        guard !key.isEmpty else { return remove(for: provider) }
        let data = Data(key.utf8)
        let update: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked]
        let status = SecItemUpdate(base(provider) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = base(provider)
        add.merge(update) { $1 }
        add[kSecAttrLabel as String] = "MacMinion \(provider.title) API key"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public func remove(for provider: AIProvider) -> Bool {
        let status = SecItemDelete(base(provider) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func base(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: Self.account(for: provider)]
    }
}
