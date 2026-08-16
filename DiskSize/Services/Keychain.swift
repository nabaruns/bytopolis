import Foundation
import Security
import LocalAuthentication

/// Keychain storage for API keys. Prefers a Touch ID / device-password gate
/// (`SecAccessControl(.userPresence)` in the data-protection keychain) and authenticates
/// **once per session** (the unlocked value is cached for the process lifetime).
///
/// The data-protection keychain requires a real signing identity, which an ad-hoc
/// "sign to run locally" build doesn't have — so we transparently fall back to the legacy
/// keychain (no biometric prompt) there. Saving always works; the biometric gate simply
/// engages once the app is signed with a Developer ID.
enum Keychain {
    private static let service = "com.nabaruns.DiskSize"
    private static var sessionCache: [String: String] = [:]
    private static let lock = NSLock()

    private static func base(_ account: String, dataProtection: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    // MARK: - Store

    static func set(_ key: String, account: String) {
        lock.withLock { sessionCache[account] = nil }
        SecItemDelete(base(account, dataProtection: true) as CFDictionary)
        SecItemDelete(base(account, dataProtection: false) as CFDictionary)

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let data = Data(trimmed.utf8)

        // 1) Preferred: biometric-gated item in the data-protection keychain.
        if let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil) {
            var q = base(account, dataProtection: true)
            q[kSecValueData as String] = data
            q[kSecAttrAccessControl as String] = access
            if SecItemAdd(q as CFDictionary, nil) == errSecSuccess { return }
        }

        // 2) Fallback: legacy keychain (works without a signing identity).
        var q = base(account, dataProtection: false)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(account: String) {
        lock.withLock { sessionCache[account] = nil }
        SecItemDelete(base(account, dataProtection: true) as CFDictionary)
        SecItemDelete(base(account, dataProtection: false) as CFDictionary)
    }

    // MARK: - Presence (no prompt)

    static func has(account: String) -> Bool {
        if lock.withLock({ sessionCache[account] != nil }) { return true }
        // data-protection keychain (skip UI)
        var q = base(account, dataProtection: true)
        q[kSecReturnData as String] = false
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        let s1 = SecItemCopyMatching(q as CFDictionary, nil)
        if s1 == errSecSuccess || s1 == errSecInteractionNotAllowed { return true }
        // legacy keychain
        var q2 = base(account, dataProtection: false)
        q2[kSecReturnData as String] = false
        return SecItemCopyMatching(q2 as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Read (authenticate once per session)

    static func unlockedKey(account: String) async -> String? {
        if let cached = lock.withLock({ sessionCache[account] }) { return cached }

        // Is it in the (biometric) data-protection keychain? Probe without prompting.
        var probe = base(account, dataProtection: true)
        probe[kSecReturnData as String] = false
        probe[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        let probeStatus = SecItemCopyMatching(probe as CFDictionary, nil)

        if probeStatus == errSecSuccess || probeStatus == errSecInteractionNotAllowed {
            let context = LAContext()
            context.localizedReason = "Unlock your API key for Bytopolis"
            guard await authenticate(context) else { return nil }
            var q = base(account, dataProtection: true)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            q[kSecUseAuthenticationContext as String] = context
            var out: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
               let data = out as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty {
                lock.withLock { sessionCache[account] = key }
                return key
            }
        }

        // Legacy keychain (no prompt).
        var q2 = base(account, dataProtection: false)
        q2[kSecReturnData as String] = true
        q2[kSecMatchLimit as String] = kSecMatchLimitOne
        var out2: CFTypeRef?
        guard SecItemCopyMatching(q2 as CFDictionary, &out2) == errSecSuccess,
              let data = out2 as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        lock.withLock { sessionCache[account] = key }
        return key
    }

    private static func authenticate(_ context: LAContext) async -> Bool {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return await withCheckedContinuation { cont in
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: context.localizedReason) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
