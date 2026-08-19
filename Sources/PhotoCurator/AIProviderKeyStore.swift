import Foundation
import Security

enum AIProviderKeyStoreError: LocalizedError {
    case invalidKey
    case unableToSave
    case unableToRead
    case unableToDelete

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            String(localized: "请输入有效的 API Key。")
        case .unableToSave:
            String(localized: "无法保存到 macOS Keychain。")
        case .unableToRead:
            String(localized: "无法从 macOS Keychain 读取 API Key。")
        case .unableToDelete:
            String(localized: "无法从 macOS Keychain 删除 API Key。")
        }
    }
}

/// 每个供应商使用独立 Keychain service；Key 不进入 UserDefaults、文件、日志或导出清单。
enum AIProviderKeyStore {
    private static let account = "photo-curator-local-mac"

    static func save(_ rawKey: String, for providerID: AIProviderID) throws {
        let key = normalizedKey(from: rawKey)
        guard key.count >= 12, let valueData = key.data(using: .utf8) else {
            throw AIProviderKeyStoreError.invalidKey
        }

        let query = baseQuery(for: providerID)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: valueData] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AIProviderKeyStoreError.unableToSave
        }

        var newItem = query
        newItem[kSecValueData as String] = valueData
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        guard SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess else {
            throw AIProviderKeyStoreError.unableToSave
        }
    }

    static func read(for providerID: AIProviderID) throws -> String? {
        var query = baseQuery(for: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            throw AIProviderKeyStoreError.unableToRead
        }
        return key
    }

    static func hasSavedKey(for providerID: AIProviderID) -> Bool {
        (try? read(for: providerID)) != nil
    }

    static func delete(for providerID: AIProviderID) throws {
        let status = SecItemDelete(baseQuery(for: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIProviderKeyStoreError.unableToDelete
        }
    }

    static func normalizedKey(from rawKey: String) -> String {
        rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func serviceName(
        for providerID: AIProviderID,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> String {
        let bundleID = bundleIdentifier ?? "com.photocurator.local"
        switch providerID {
        case .volcengineArk:
            // 保持旧 service 名，升级后现有方舟 Key 无需迁移。
            return "\(bundleID).ark-api-key"
        case .miniMax:
            return "\(bundleID).ai-api-key.minimax"
        case .openAI:
            return "\(bundleID).ai-api-key.openai"
        case .anthropic:
            return "\(bundleID).ai-api-key.anthropic"
        case .googleGemini:
            return "\(bundleID).ai-api-key.google-gemini"
        case .alibabaModelStudio:
            return "\(bundleID).ai-api-key.alibaba-model-studio"
        case .xAI:
            return "\(bundleID).ai-api-key.xai"
        case .moonshotKimi:
            return "\(bundleID).ai-api-key.moonshot-kimi"
        case .zhipuGLM:
            return "\(bundleID).ai-api-key.zhipu-glm"
        case .tencentHunyuan:
            return "\(bundleID).ai-api-key.tencent-hunyuan"
        case .customOpenAICompatible:
            return "\(bundleID).ai-api-key.custom-openai-compatible"
        }
    }

    private static func baseQuery(for providerID: AIProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: providerID),
            kSecAttrAccount as String: account,
        ]
    }
}
