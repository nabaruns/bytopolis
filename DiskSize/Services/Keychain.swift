import Foundation
import Security
import LocalAuthentication

/// Keychain storage for API keys, protected with Touch ID / Apple Watch / device password
/// (`SecAccessControl(.userPresence)`). The unlocked value is cached for the process
/// lifetime, so you authenticate **once per session** rather than on every request.
///
/// Note: biometric-protected items are bound to the app's signing identity — with an
/// ad-hoc "sign to run locally" build, re-signing can invalidate them and you'll re-enter
/// the key. That's stable once signed with a Developer ID.
enum Keychain {
    private static let service = "com.nabaruns.DiskSize"
    private static var sessionCache: [String: String] = [:]
    private static let lock = NSLock()

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    // MARK: - Store

    static func set(_ key: String, account: String) {
        lock.lock(); sessionCache[account] = nil; lock.unlock()

        SecItemDelete(baseQuery(account) as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var add = baseQuery(account)
        add[kSecValueData as String] = Data(trimmed.utf8)

        // Prefer a biometric/user-presence access control; fall back to a plain accessible
        // attribute if the platform can't create one (keeps the app usable everywhere).
        if let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil) {
            add[kSecAttrAccessControl as String] = access
            if SecItemAdd(add as CFDictionary, nil) == errSecSuccess { return }
            add[kSecAttrAccessControl as String] = nil   // retry unprotected on failure
        }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(account: String) {
        lock.lock(); sessionCache[account] = nil; lock.unlock()
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    // MARK: - Presence check (no prompt)

    /// Whether a key is stored, without triggering an auth prompt (skips the UI).
    static func has(account: String) -> Bool {
        if lock.withLock({ sessionCache[account] != nil }) { return true }
        var q = baseQuery(account)
        q[kSecReturnData as String] = false
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    // MARK: - Read (authenticate once per session)

    /// Return the key, prompting for Touch ID / device password the first time this session
    /// and caching it thereafter. Returns nil if absent or the user cancels auth.
    static func unlockedKey(account: String) async -> String? {
        if let cached = lock.withLock({ sessionCache[account] }) { return cached }

        let context = LAContext()
        context.localizedReason = "Unlock your API key for DiskSize"
        guard await authenticate(context) else { return nil }

        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationContext as String] = context

        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }

        lock.withLock { sessionCache[account] = key }
        return key
    }

    private static func authenticate(_ context: LAContext) async -> Bool {
        var error: NSError?
        // If no biometrics/passcode is configured, don't block access.
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
