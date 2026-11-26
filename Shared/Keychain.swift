import Foundation
import Security

/// Small wrapper over the macOS data-protection keychain, shared with the widgets.
enum Keychain {
    enum Key: String {
        case stravaClientID, stravaClientSecret, stravaAccess, stravaRefresh, stravaExpires
        case adpURL, adpKey
        case googleClientID, googleClientSecret, googleAccess, googleRefresh, googleExpires, googleCalendarID
        case anthropicKey
    }

    static func set(_ value: String?, for key: Key) {
        let q = base(key)
        SecItemDelete(q as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s = String(data: d, encoding: .utf8)
        return (s?.isEmpty ?? true) ? nil : s
    }

    private static func base(_ key: Key) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.binoy.healthfitness",
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let g = AppConfig.keychainGroup { q[kSecAttrAccessGroup as String] = g }
        return q
    }
}
