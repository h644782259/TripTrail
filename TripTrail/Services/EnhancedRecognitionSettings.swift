import Foundation
import Security

enum EnhancedRecognitionSettings {
    static let enabledDefaultsKey = "enhancedItineraryRecognitionEnabled"

    static var isEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            let storedPreference = defaults.object(forKey: enabledDefaultsKey) == nil
                ? nil
                : defaults.bool(forKey: enabledDefaultsKey)
            return resolvedIsEnabled(
                storedPreference: storedPreference,
                hasAPIKey: ZhipuAPIKeyStore.hasAPIKey
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
