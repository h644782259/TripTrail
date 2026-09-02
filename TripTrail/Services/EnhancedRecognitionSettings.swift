import Foundation
import Security

enum EnhancedRecognitionSettings {
    static let enabledDefaultsKey = "enhancedItineraryRecognitionEnabled"
    static let providerDefaultsKey = "enhancedItineraryRecognitionProvider"

    enum Provider: String, CaseIterable, Identifiable {
        case zhipu
        case deepseek
        var id: String { rawValue }
        var displayName: String { self == .zhipu ? "智谱" : "DeepSeek" }
        var apiKeyLabel: String { "\(displayName) API Key" }
    }

    static var provider: Provider {
        get { Provider(rawValue: UserDefaults.standard.string(forKey: providerDefaultsKey) ?? "") ?? .zhipu }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerDefaultsKey) }
    }

    static var activeAPIKey: String? {
        provider == .zhipu ? ZhipuAPIKeyStore.load() : DeepSeekAPIKeyStore.load()
    }

    static var isEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            let storedPreference = defaults.object(forKey: enabledDefaultsKey) == nil
                ? nil
                : defaults.bool(forKey: enabledDefaultsKey)
            return resolvedIsEnabled(
                storedPreference: storedPreference,
                hasAPIKey: activeAPIKey?.isEmpty == false
            )
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey) }
    }

    static func resolvedIsEnabled(storedPreference: Bool?, hasAPIKey: Bool) -> Bool {
        guard hasAPIKey else { return false }
        return storedPreference ?? true
    }
}

enum ZhipuAPIKeyStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "错误码 \(status)"
            return "无法保存智谱 API Key：\(detail)"
        }
    }
}

enum ZhipuAPIKeyStore {
    private static let service = "com.personal.TripTrail.zhipu"
    private static let account = "vision-api-key"
#if targetEnvironment(simulator)
    // Simulator builds installed from a CODE_SIGNING_ALLOWED=NO build do not have
    // an application-identifier entitlement, so Security returns
    // errSecMissingEntitlement. Keep the API key available for local testing
    // without weakening storage on a real iPhone.
    private static let simulatorFallbackDefaultsKey = "zhipuAPIKey.simulatorFallback"
#endif

    static var hasAPIKey: Bool {
        load()?.isEmpty == false
    }

    static func load() -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            baseQuery.merging([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]) { _, new in new } as CFDictionary,
            &result
        )
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }
#if targetEnvironment(simulator)
        if status == errSecMissingEntitlement || status == errSecItemNotFound {
            return UserDefaults.standard.string(forKey: simulatorFallbackDefaultsKey)
        }
#endif
        return nil
    }

    static func save(_ apiKey: String) throws {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            try delete()
            return
        }
        let data = Data(normalized.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            clearSimulatorFallback()
            return
        }
#if targetEnvironment(simulator)
        if updateStatus == errSecMissingEntitlement {
            saveToSimulatorFallback(normalized)
            return
        }
#endif
        guard updateStatus == errSecItemNotFound else {
            throw ZhipuAPIKeyStoreError.keychain(updateStatus)
        }

        let addStatus = SecItemAdd(
            baseQuery.merging([
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]) { _, new in new } as CFDictionary,
            nil
        )
        if addStatus == errSecSuccess {
            clearSimulatorFallback()
            return
        }
#if targetEnvironment(simulator)
        if addStatus == errSecMissingEntitlement {
            saveToSimulatorFallback(normalized)
            return
        }
#endif
        guard addStatus == errSecSuccess else {
            throw ZhipuAPIKeyStoreError.keychain(addStatus)
        }
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
#if targetEnvironment(simulator)
        if status == errSecMissingEntitlement || status == errSecItemNotFound {
            clearSimulatorFallback()
            return
        }
#endif
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ZhipuAPIKeyStoreError.keychain(status)
        }
        clearSimulatorFallback()
    }

    private static func clearSimulatorFallback() {
#if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: simulatorFallbackDefaultsKey)
#endif
    }

#if targetEnvironment(simulator)
    private static func saveToSimulatorFallback(_ apiKey: String) {
        UserDefaults.standard.set(apiKey, forKey: simulatorFallbackDefaultsKey)
    }
#endif

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum DeepSeekAPIKeyStore {
    private static let service = "com.personal.TripTrail.deepseek"
    private static let account = "api-key"
    static var hasAPIKey: Bool { load()?.isEmpty == false }
    #if targetEnvironment(simulator)
    private static let fallbackKey = "deepseekAPIKey.simulatorFallback"
    #endif
    static func load() -> String? {
        let value = RecognitionAPIKeyStore.load(service: service, account: account)
        #if targetEnvironment(simulator)
        return value ?? UserDefaults.standard.string(forKey: fallbackKey)
        #else
        return value
        #endif
    }
    static func save(_ key: String) throws {
        do { try RecognitionAPIKeyStore.save(key, service: service, account: account, error: { .keychain($0) }); clearFallback() }
        catch ZhipuAPIKeyStoreError.keychain(let status) where status == errSecMissingEntitlement {
            #if targetEnvironment(simulator)
            UserDefaults.standard.set(key, forKey: fallbackKey)
            #else
            throw ZhipuAPIKeyStoreError.keychain(status)
            #endif
        }
    }
    static func delete() throws { try RecognitionAPIKeyStore.delete(service: service, account: account, error: { .keychain($0) }); clearFallback() }
    private static func clearFallback() {
        #if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        #endif
    }
}

private enum RecognitionAPIKeyStore {
    static func load(service: String, account: String) -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String, service: String, account: String, error: (OSStatus) -> ZhipuAPIKeyStoreError) throws {
        let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw error(update) }
        let add = SecItemAdd(query.merging([kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { _, new in new } as CFDictionary, nil)
        guard add == errSecSuccess else { throw error(add) }
    }
    static func delete(service: String, account: String, error: (OSStatus) -> ZhipuAPIKeyStoreError) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
    }
}
