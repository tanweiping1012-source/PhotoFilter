import Foundation

enum AIProviderID: String, Codable, CaseIterable, Identifiable {
    case volcengineArk = "volcengine-ark"
    case miniMax = "minimax"
    case openAI = "openai"
    case anthropic = "anthropic"
    case googleGemini = "google-gemini"
    case alibabaModelStudio = "alibaba-model-studio"
    case xAI = "xai"
    case moonshotKimi = "moonshot-kimi"
    case zhipuGLM = "zhipu-glm"
    case tencentHunyuan = "tencent-hunyuan"
    case customOpenAICompatible = "custom-openai-compatible"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .volcengineArk:
            String(localized: "火山方舟")
        case .miniMax:
            "MiniMax"
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .googleGemini:
            "Google"
        case .alibabaModelStudio:
            String(localized: "阿里云百炼")
        case .xAI:
            "xAI"
        case .moonshotKimi:
            "Kimi"
        case .zhipuGLM:
            String(localized: "智谱 GLM")
        case .tencentHunyuan:
            String(localized: "腾讯混元")
        case .customOpenAICompatible:
            String(localized: "自定义兼容接口")
        }
    }
}

enum AIModelID: String, Codable, CaseIterable, Identifiable {
    case doubaoSeed21Pro = "doubao-seed-2-1-pro"
    case doubaoSeed20Lite = "doubao-seed-2-0-lite"
    case miniMaxM3 = "minimax-m3"
    case openAIGPT56Sol = "openai-gpt-5-6-sol"
    case openAIGPT56Terra = "openai-gpt-5-6-terra"
    case openAIGPT56Luna = "openai-gpt-5-6-luna"
    case openAIGPT55 = "openai-gpt-5-5"
    case openAIGPT54 = "openai-gpt-5-4"
    case openAIGPT54Mini = "openai-gpt-5-4-mini"
    case openAIGPT54Nano = "openai-gpt-5-4-nano"
    case openAIOther = "openai-other"
    case anthropicClaudeFable5 = "anthropic-claude-fable-5"
    case anthropicClaudeOpus5 = "anthropic-claude-opus-5"
    case anthropicClaudeOpus48 = "anthropic-claude-opus-4-8"
    case anthropicClaudeOpus47 = "anthropic-claude-opus-4-7"
    case anthropicClaudeOpus46 = "anthropic-claude-opus-4-6"
    case anthropicClaudeOpus45 = "anthropic-claude-opus-4-5"
    case anthropicClaudeSonnet5 = "anthropic-claude-sonnet-5"
    case anthropicClaudeSonnet46 = "anthropic-claude-sonnet-4-6"
    case anthropicClaudeSonnet45 = "anthropic-claude-sonnet-4-5"
    case anthropicClaudeHaiku45 = "anthropic-claude-haiku-4-5"
    case anthropicOther = "anthropic-other"
    case googleGemini31ProPreview = "google-gemini-3-1-pro-preview"
    case googleGemini37Flash = "google-gemini-3-7-flash"
    case googleGemini35FlashLite = "google-gemini-3-5-flash-lite"
    case alibabaQwen38Max = "alibaba-qwen-3-8-max"
    case alibabaQwen37Plus = "alibaba-qwen-3-7-plus"
    case alibabaQwen37Flash = "alibaba-qwen-3-7-flash"
    case xAIGrok46 = "xai-grok-4-6"
    case moonshotKimiK3 = "moonshot-kimi-k3"
    case moonshotKimiK26 = "moonshot-kimi-k2-6"
    case moonshotKimiK25 = "moonshot-kimi-k2-5"
    case zhipuGLM46V = "zhipu-glm-4-6v"
    case zhipuGLM46VFlashX = "zhipu-glm-4-6v-flashx"
    case zhipuGLM46VFlash = "zhipu-glm-4-6v-flash"
    case tencentHunyuanVision = "tencent-hunyuan-vision"
    case customOpenAICompatible = "custom-openai-compatible"

    var id: String { rawValue }
}

enum AIProtocolID: String, Codable, Equatable {
    case arkResponses
    case miniMaxChatCompletions
    case openAICompatibleChatCompletions
    case anthropicMessages
}

enum OpenAICompatibilityProfile: String, Codable, Equatable {
    case openAI
    case gemini
    case qwen
    case xAI
    case moonshot
    case zhipu
    case hunyuan
    case custom
}

struct AIModelDescriptor: Identifiable, Equatable {
    let id: AIModelID
    let providerID: AIProviderID
    let apiModelID: String
    let displayName: String
    let endpoint: URL
    let protocolID: AIProtocolID
    let compatibilityProfile: OpenAICompatibilityProfile?
    let supportsImageInput: Bool
    let supportsJSONResponseFormat: Bool
    let isReady: Bool

    var providerAndModelDisplayName: String {
        "\(providerID.displayName) · \(displayName)"
    }

    var endpointHost: String {
        endpoint.host ?? endpoint.absoluteString
    }
}

enum AIModelCatalog {
    static let defaultModelID = AIModelID.doubaoSeed20Lite

    private static let builtInModels: [AIModelDescriptor] = [
        AIModelDescriptor(
            id: .doubaoSeed21Pro,
            providerID: .volcengineArk,
            apiModelID: "doubao-seed-2-1-pro-260628",
            displayName: "Doubao-Seed-2.1 Pro",
            endpoint: URL(string: "https://ark.cn-beijing.volces.com/api/v3/responses")!,
            protocolID: .arkResponses,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .doubaoSeed20Lite,
            providerID: .volcengineArk,
            apiModelID: "doubao-seed-2-0-lite-260428",
            displayName: "Doubao-Seed-2.0 Lite",
            endpoint: URL(string: "https://ark.cn-beijing.volces.com/api/v3/responses")!,
            protocolID: .arkResponses,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .miniMaxM3,
            providerID: .miniMax,
            apiModelID: "MiniMax-M3",
            displayName: "MiniMax-M3",
            endpoint: URL(string: "https://api.minimaxi.com/v1/chat/completions")!,
            protocolID: .miniMaxChatCompletions,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .openAIGPT56Sol,
            providerID: .openAI,
            apiModelID: "gpt-5.6-sol",
            displayName: "GPT-5.6 Sol",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .openAI,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .openAIGPT56Terra,
            providerID: .openAI,
            apiModelID: "gpt-5.6-terra",
            displayName: "GPT-5.6 Terra",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .openAI,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .openAIGPT56Luna,
            providerID: .openAI,
            apiModelID: "gpt-5.6-luna",
            displayName: "GPT-5.6 Luna",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .openAI,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .openAIGPT55,
            providerID: .openAI,
            apiModelID: "gpt-5.5",
            displayName: "GPT-5.5",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .openAI,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .openAIGPT54,
            providerID: .openAI,
            apiModelID: "gpt-5.4",
            displayName: "GPT-5.4",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .openAI,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .openAIGPT54Mini,
            providerID: .openAI,
            apiModelID: "gpt-5.4-mini",
            displayName: "GPT-5.4 mini",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .openAI,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .openAIGPT54Nano,
            providerID: .openAI,
            apiModelID: "gpt-5.4-nano",
            displayName: "GPT-5.4 nano",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .openAI,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .anthropicClaudeFable5,
            providerID: .anthropic,
            apiModelID: "claude-fable-5",
            displayName: "Claude Fable 5",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            protocolID: .anthropicMessages,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .anthropicClaudeOpus5,
            providerID: .anthropic,
            apiModelID: "claude-opus-5",
            displayName: "Claude Opus 5",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            protocolID: .anthropicMessages,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .anthropicClaudeOpus48,
            providerID: .anthropic,
            apiModelID: "claude-opus-4-8",
            displayName: "Claude Opus 4.8",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            protocolID: .anthropicMessages,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .anthropicClaudeOpus47,
            providerID: .anthropic,
            apiModelID: "claude-opus-4-7",
            displayName: "Claude Opus 4.7",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            protocolID: .anthropicMessages,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .anthropicClaudeOpus46,
            providerID: .anthropic,
            apiModelID: "claude-opus-4-6",
            displayName: "Claude Opus 4.6",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            protocolID: .anthropicMessages,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .anthropicClaudeOpus45,
            providerID: .anthropic,
            apiModelID: "claude-opus-4-5",
            displayName: "Claude Opus 4.5",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            protocolID: .anthropicMessages,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .anthropicClaudeSonnet5,
            providerID: .anthropic,
            apiModelID: "claude-sonnet-5",
            displayName: "Claude Sonnet 5",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            protocolID: .anthropicMessages,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .anthropicClaudeSonnet46,
            providerID: .anthropic,
            apiModelID: "claude-sonnet-4-6",
            displayName: "Claude Sonnet 4.6",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            protocolID: .anthropicMessages,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .anthropicClaudeSonnet45,
            providerID: .anthropic,
            apiModelID: "claude-sonnet-4-5",
            displayName: "Claude Sonnet 4.5",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            protocolID: .anthropicMessages,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .anthropicClaudeHaiku45,
            providerID: .anthropic,
            apiModelID: "claude-haiku-4-5",
            displayName: "Claude Haiku 4.5",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            protocolID: .anthropicMessages,
            compatibilityProfile: nil,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .googleGemini31ProPreview,
            providerID: .googleGemini,
            apiModelID: "gemini-3.1-pro-preview",
            displayName: "Gemini 3.1 Pro Preview",
            endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .gemini,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .googleGemini37Flash,
            providerID: .googleGemini,
            apiModelID: "gemini-3.7-flash",
            displayName: "Gemini 3.7 Flash",
            endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .gemini,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .googleGemini35FlashLite,
            providerID: .googleGemini,
            apiModelID: "gemini-3.5-flash-lite",
            displayName: "Gemini 3.5 Flash-Lite",
            endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .gemini,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .alibabaQwen38Max,
            providerID: .alibabaModelStudio,
            apiModelID: "qwen3.8-max",
            displayName: "Qwen3.8 Max",
            endpoint: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .qwen,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .alibabaQwen37Plus,
            providerID: .alibabaModelStudio,
            apiModelID: "qwen3.7-plus",
            displayName: "Qwen3.7 Plus",
            endpoint: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .qwen,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .alibabaQwen37Flash,
            providerID: .alibabaModelStudio,
            apiModelID: "qwen3.7-flash",
            displayName: "Qwen3.7 Flash",
            endpoint: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .qwen,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .xAIGrok46,
            providerID: .xAI,
            apiModelID: "grok-4.6",
            displayName: "Grok 4.6",
            endpoint: URL(string: "https://api.x.ai/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .xAI,
            supportsImageInput: true,
            supportsJSONResponseFormat: true,
            isReady: true
        ),
        AIModelDescriptor(
            id: .moonshotKimiK3,
            providerID: .moonshotKimi,
            apiModelID: "kimi-k3",
            displayName: "Kimi K3",
            endpoint: URL(string: "https://api.moonshot.ai/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .moonshot,
            supportsImageInput: true,
            supportsJSONResponseFormat: false,
            isReady: true
        ),
        AIModelDescriptor(
            id: .moonshotKimiK26,
            providerID: .moonshotKimi,
            apiModelID: "kimi-k2.6",
            displayName: "Kimi K2.6",
            endpoint: URL(string: "https://api.moonshot.ai/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .moonshot,
            supportsImageInput: true,
            supportsJSONResponseFormat: false,
            isReady: true
        ),
        AIModelDescriptor(
            id: .moonshotKimiK25,
            providerID: .moonshotKimi,
            apiModelID: "kimi-k2.5",
            displayName: "Kimi K2.5",
            endpoint: URL(string: "https://api.moonshot.ai/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .moonshot,
            supportsImageInput: true,
            supportsJSONResponseFormat: false,
            isReady: true
        ),
        AIModelDescriptor(
            id: .zhipuGLM46V,
            providerID: .zhipuGLM,
            apiModelID: "glm-4.6v",
            displayName: "GLM-4.6V",
            endpoint: URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .zhipu,
            supportsImageInput: true,
            supportsJSONResponseFormat: false,
            isReady: true
        ),
        AIModelDescriptor(
            id: .zhipuGLM46VFlashX,
            providerID: .zhipuGLM,
            apiModelID: "glm-4.6v-flashx",
            displayName: "GLM-4.6V-FlashX",
            endpoint: URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .zhipu,
            supportsImageInput: true,
            supportsJSONResponseFormat: false,
            isReady: true
        ),
        AIModelDescriptor(
            id: .zhipuGLM46VFlash,
            providerID: .zhipuGLM,
            apiModelID: "glm-4.6v-flash",
            displayName: "GLM-4.6V-Flash",
            endpoint: URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .zhipu,
            supportsImageInput: true,
            supportsJSONResponseFormat: false,
            isReady: true
        ),
        AIModelDescriptor(
            id: .tencentHunyuanVision,
            providerID: .tencentHunyuan,
            apiModelID: "hunyuan-vision",
            displayName: "Hunyuan Vision",
            endpoint: URL(string: "https://api.hunyuan.cloud.tencent.com/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .hunyuan,
            supportsImageInput: true,
            supportsJSONResponseFormat: false,
            isReady: true
        ),
    ]

    static var availableModels: [AIModelDescriptor] {
        models(
            customConfiguration:
                CustomOpenAICompatibleConfigurationStore.load(),
            providerAdditionalConfiguration:
                ProviderAdditionalModelConfigurationStore.load()
        )
    }

    static var availableProviders: [AIProviderID] {
        availableProviders(
            customConfiguration:
                CustomOpenAICompatibleConfigurationStore.load()
        )
    }

    static func availableProviders(
        customConfiguration: CustomOpenAICompatibleConfiguration,
        providerAdditionalConfiguration:
            ProviderAdditionalModelConfiguration =
                ProviderAdditionalModelConfigurationStore.load()
    ) -> [AIProviderID] {
        let modelProviders = Set(
            models(
                customConfiguration: customConfiguration,
                providerAdditionalConfiguration:
                    providerAdditionalConfiguration
            ).map(\.providerID)
        )
        return AIProviderID.allCases.filter(modelProviders.contains)
    }

    static func models(
        customConfiguration: CustomOpenAICompatibleConfiguration,
        providerAdditionalConfiguration:
            ProviderAdditionalModelConfiguration =
                ProviderAdditionalModelConfigurationStore.load()
    ) -> [AIModelDescriptor] {
        builtInModels
            + [
                providerAdditionalConfiguration.modelDescriptor(
                    for: .openAI
                ),
                providerAdditionalConfiguration.modelDescriptor(
                    for: .anthropic
                ),
                customConfiguration.modelDescriptor,
            ]
    }

    static func models(
        for providerID: AIProviderID,
        customConfiguration: CustomOpenAICompatibleConfiguration
            = CustomOpenAICompatibleConfigurationStore.load(),
        providerAdditionalConfiguration:
            ProviderAdditionalModelConfiguration =
                ProviderAdditionalModelConfigurationStore.load()
    ) -> [AIModelDescriptor] {
        models(
            customConfiguration: customConfiguration,
            providerAdditionalConfiguration:
                providerAdditionalConfiguration
        ).filter {
            $0.providerID == providerID
        }
    }

    static func defaultModelID(
        for providerID: AIProviderID,
        customConfiguration: CustomOpenAICompatibleConfiguration
            = CustomOpenAICompatibleConfigurationStore.load(),
        providerAdditionalConfiguration:
            ProviderAdditionalModelConfiguration =
                ProviderAdditionalModelConfigurationStore.load()
    ) -> AIModelID {
        models(
            for: providerID,
            customConfiguration: customConfiguration,
            providerAdditionalConfiguration:
                providerAdditionalConfiguration
        ).first?.id ?? defaultModelID
    }

    static func model(
        for id: AIModelID,
        customConfiguration: CustomOpenAICompatibleConfiguration
            = CustomOpenAICompatibleConfigurationStore.load(),
        providerAdditionalConfiguration:
            ProviderAdditionalModelConfiguration =
                ProviderAdditionalModelConfigurationStore.load()
    ) -> AIModelDescriptor {
        models(
            customConfiguration: customConfiguration,
            providerAdditionalConfiguration:
                providerAdditionalConfiguration
        )
            .first(where: { $0.id == id })
            ?? builtInModels.first(where: { $0.id == defaultModelID })!
    }
}

struct ProviderAdditionalModelConfiguration: Codable, Equatable {
    var openAIModelID: String
    var openAIDisplayName: String
    var anthropicModelID: String
    var anthropicDisplayName: String

    static let empty = ProviderAdditionalModelConfiguration(
        openAIModelID: "",
        openAIDisplayName: "",
        anthropicModelID: "",
        anthropicDisplayName: ""
    )

    func modelID(for providerID: AIProviderID) -> String {
        switch providerID {
        case .openAI:
            openAIModelID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        case .anthropic:
            anthropicModelID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        default:
            ""
        }
    }

    func displayName(for providerID: AIProviderID) -> String {
        let configuredName = configuredDisplayName(for: providerID)
        if !configuredName.isEmpty {
            return configuredName
        }
        let configuredModelID = modelID(for: providerID)
        return configuredModelID.isEmpty
            ? String(localized: "其他模型 ID…")
            : configuredModelID
    }

    func configuredDisplayName(
        for providerID: AIProviderID
    ) -> String {
        let rawName: String
        switch providerID {
        case .openAI:
            rawName = openAIDisplayName
        case .anthropic:
            rawName = anthropicDisplayName
        default:
            rawName = ""
        }
        return rawName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    mutating func set(
        providerID: AIProviderID,
        modelID: String,
        displayName: String
    ) {
        switch providerID {
        case .openAI:
            openAIModelID = modelID
            openAIDisplayName = displayName
        case .anthropic:
            anthropicModelID = modelID
            anthropicDisplayName = displayName
        default:
            break
        }
    }

    func modelDescriptor(
        for providerID: AIProviderID
    ) -> AIModelDescriptor {
        let apiModelID = modelID(for: providerID)
        switch providerID {
        case .openAI:
            return AIModelDescriptor(
                id: .openAIOther,
                providerID: .openAI,
                apiModelID: apiModelID,
                displayName: displayName(for: providerID),
                endpoint: URL(
                    string:
                        "https://api.openai.com/v1/chat/completions"
                )!,
                protocolID: .openAICompatibleChatCompletions,
                compatibilityProfile: .openAI,
                supportsImageInput: true,
                supportsJSONResponseFormat: true,
                isReady: !apiModelID.isEmpty
            )
        case .anthropic:
            return AIModelDescriptor(
                id: .anthropicOther,
                providerID: .anthropic,
                apiModelID: apiModelID,
                displayName: displayName(for: providerID),
                endpoint: URL(
                    string: "https://api.anthropic.com/v1/messages"
                )!,
                protocolID: .anthropicMessages,
                compatibilityProfile: nil,
                supportsImageInput: true,
                supportsJSONResponseFormat: true,
                isReady: !apiModelID.isEmpty
            )
        default:
            preconditionFailure(
                "Additional models are unsupported for \(providerID)"
            )
        }
    }
}

enum ProviderAdditionalModelConfigurationStore {
    private static let configurationKey =
        "provider-additional-model-configuration-v1"

    static func load(
        defaults: UserDefaults = .standard
    ) -> ProviderAdditionalModelConfiguration {
        guard let data = defaults.data(forKey: configurationKey),
              let configuration = try? JSONDecoder().decode(
                  ProviderAdditionalModelConfiguration.self,
                  from: data
              ) else {
            return .empty
        }
        return configuration
    }

    static func save(
        _ configuration: ProviderAdditionalModelConfiguration,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }
        defaults.set(data, forKey: configurationKey)
    }
}

struct CustomOpenAICompatibleConfiguration: Codable, Equatable {
    var displayName: String
    var endpointString: String
    var apiModelID: String

    static let empty = CustomOpenAICompatibleConfiguration(
        displayName: "",
        endpointString: "",
        apiModelID: ""
    )

    var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedModelID: String {
        apiModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var validatedEndpoint: URL? {
        let rawValue = endpointString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let components = URLComponents(string: rawValue),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }
        let isLoopback = host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
        guard scheme == "https" || (scheme == "http" && isLoopback),
              components.path.hasSuffix("/chat/completions"),
              let url = components.url else {
            return nil
        }
        return url
    }

    var isReady: Bool {
        validatedEndpoint != nil && !normalizedModelID.isEmpty
    }

    var modelDescriptor: AIModelDescriptor {
        AIModelDescriptor(
            id: .customOpenAICompatible,
            providerID: .customOpenAICompatible,
            apiModelID: normalizedModelID,
            displayName: normalizedDisplayName.isEmpty
                ? String(localized: "自定义 OpenAI-compatible")
                : normalizedDisplayName,
            endpoint: validatedEndpoint
                ?? URL(string: "https://invalid.local/v1/chat/completions")!,
            protocolID: .openAICompatibleChatCompletions,
            compatibilityProfile: .custom,
            supportsImageInput: true,
            supportsJSONResponseFormat: false,
            isReady: isReady
        )
    }
}

enum CustomOpenAICompatibleConfigurationStore {
    private static let configurationKey
        = "custom-openai-compatible-configuration-v1"

    static func load(
        defaults: UserDefaults = .standard
    ) -> CustomOpenAICompatibleConfiguration {
        guard let data = defaults.data(forKey: configurationKey),
              let configuration = try? JSONDecoder().decode(
                  CustomOpenAICompatibleConfiguration.self,
                  from: data
              ) else {
            return .empty
        }
        return configuration
    }

    static func save(
        _ configuration: CustomOpenAICompatibleConfiguration,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }
        defaults.set(data, forKey: configurationKey)
    }
}

enum AIModelSelectionStore {
    private static let selectedModelKey = "selected-ai-model-v1"

    static func load(defaults: UserDefaults = .standard) -> AIModelID {
        guard let rawValue = defaults.string(forKey: selectedModelKey),
              let modelID = AIModelID(rawValue: rawValue),
              AIModelCatalog.availableModels.contains(where: { $0.id == modelID }) else {
            return AIModelCatalog.defaultModelID
        }
        return modelID
    }

    static func save(
        _ modelID: AIModelID,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(modelID.rawValue, forKey: selectedModelKey)
    }
}

enum AIModelVerificationStore {
    private static let verifiedModelIDsKey =
        "verified-ai-model-identities-v2"

    static func isVerified(
        _ model: AIModelDescriptor,
        defaults: UserDefaults = .standard
    ) -> Bool {
        Set(
            defaults.stringArray(forKey: verifiedModelIDsKey) ?? []
        ).contains(verificationIdentity(for: model))
    }

    static func markVerified(
        _ model: AIModelDescriptor,
        defaults: UserDefaults = .standard
    ) {
        var verifiedIDs = Set(
            defaults.stringArray(forKey: verifiedModelIDsKey) ?? []
        )
        verifiedIDs.insert(verificationIdentity(for: model))
        defaults.set(
            verifiedIDs.sorted(),
            forKey: verifiedModelIDsKey
        )
    }

    static func clear(
        providerID: AIProviderID,
        defaults: UserDefaults = .standard
    ) {
        let remaining = Set(
            defaults.stringArray(forKey: verifiedModelIDsKey) ?? []
        ).filter {
            !$0.hasPrefix("\(providerID.rawValue)|")
        }
        defaults.set(
            Array(remaining).sorted(),
            forKey: verifiedModelIDsKey
        )
    }

    static func verificationIdentity(
        for model: AIModelDescriptor
    ) -> String {
        "\(model.providerID.rawValue)|\(model.apiModelID)"
    }
}

enum AIReviewPreviewSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:
            String(localized: "小")
        case .medium:
            String(localized: "中")
        case .large:
            String(localized: "大")
        }
    }

    var maximumPixelSize: Int {
        switch self {
        case .small: 512
        case .medium: 1_024
        case .large: 1_536
        }
    }

    var miniMaxDetail: String {
        switch self {
        case .small: "low"
        case .medium: "default"
        case .large: "high"
        }
    }

    var displayName: String {
        String(localized: "\(title) · \(maximumPixelSize)px")
    }

    var guidance: String {
        switch self {
        case .small:
            String(localized: "适合主体与整体构图；上传最少，通常费用最低。")
        case .medium:
            String(localized: "适合多人照片与一般细节；在识别、速度和费用之间平衡。")
        case .large:
            String(localized: "适合远景、小主体与纹理；上传、等待和潜在费用最高。")
        }
    }
}

enum AIReviewPreviewSizeStore {
    private static let selectedSizeKey = "selected-ai-preview-size-v1"

    static func load(defaults: UserDefaults = .standard) -> AIReviewPreviewSize {
        guard let rawValue = defaults.string(forKey: selectedSizeKey),
              let size = AIReviewPreviewSize(rawValue: rawValue) else {
            return .small
        }
        return size
    }

    static func save(
        _ size: AIReviewPreviewSize,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(size.rawValue, forKey: selectedSizeKey)
    }
}

/// AI 请求专用的 URLSession。
///
/// `URLSession.shared` 会把响应交给共享的磁盘 `URLCache`、Cookie 存储和凭据存储——
/// 这和“AI 原始响应、供应商会话状态一律不落盘”的承诺冲突。这里用 ephemeral 配置从构造上保证它。
enum AIReviewURLSession {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        // 5 张 1536px 图片加结构化 JSON 输出，在较慢的模型上会超过 60 秒的系统默认值。
        // 超时会触发自动重试，等于把同一批图片重新发一遍、重新付一次费，所以宁可等久一点。
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()
}

enum AIReviewConfiguration {
    static let maximumPhotosPerReview = 5
    /// 请求之间的基础间隔。固定 60 秒会让 48 张候选跑掉十分钟，而绝大多数供应商并不需要这么保守；
    /// 真正遇到限流时由 `AIFinalSelectionRetryPolicy` 按 `Retry-After` 或指数退避收紧节奏。
    static let minimumReviewInterval: TimeInterval = 4
    /// 触发限流后的冷却上限，避免退避无限增长。
    static let maximumReviewInterval: TimeInterval = 60
}
