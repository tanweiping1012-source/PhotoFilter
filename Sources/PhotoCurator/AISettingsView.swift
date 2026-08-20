import SwiftUI

struct AISettingsView: View {
    @Binding var selectedModelID: AIModelID
    @Binding var selectedPreviewSize: AIReviewPreviewSize
    let isConfigurationLocked: Bool
    let didChangeConfiguration: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var hasSavedKey = false
    @State private var isSelectedModelVerified = false
    @State private var statusMessage: String?
    @State private var isVerifyingConnection = false
    @State private var customDisplayName = ""
    @State private var customEndpoint = ""
    @State private var customModelID = ""
    @State private var providerAdditionalConfiguration =
        ProviderAdditionalModelConfiguration.empty
    @State private var discoveredModels: [DiscoveredAIModel] = []
    @State private var isDiscoveringModels = false

    private var selectedModel: AIModelDescriptor {
        AIModelCatalog.model(
            for: selectedModelID,
            customConfiguration: customConfiguration,
            providerAdditionalConfiguration:
                providerAdditionalConfiguration
        )
    }

    private var customConfiguration: CustomOpenAICompatibleConfiguration {
        CustomOpenAICompatibleConfiguration(
            displayName: customDisplayName,
            endpointString: customEndpoint,
            apiModelID: customModelID
        )
    }

    private var selectedProviderID: Binding<AIProviderID> {
        Binding(
            get: { selectedModel.providerID },
            set: { providerID in
                selectedModelID = AIModelCatalog.defaultModelID(
                    for: providerID,
                    customConfiguration: customConfiguration,
                    providerAdditionalConfiguration:
                        providerAdditionalConfiguration
                )
            }
        )
    }

    private var providerModels: [AIModelDescriptor] {
        AIModelCatalog.models(
            for: selectedModel.providerID,
            customConfiguration: customConfiguration,
            providerAdditionalConfiguration:
                providerAdditionalConfiguration
        )
    }

    private var availableProviders: [AIProviderID] {
        AIModelCatalog.availableProviders(
            customConfiguration: customConfiguration,
            providerAdditionalConfiguration:
                providerAdditionalConfiguration
        )
    }

    private var supportsModelDiscovery: Bool {
        AIModelDiscoveryService.supports(selectedModel.providerID)
    }

    private var isAdditionalModelSelected: Bool {
        selectedModelID == .openAIOther
            || selectedModelID == .anthropicOther
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI评分设置")
                    .font(Typography.paneTitle)
                Text("先选择品牌，再选择支持图片输入的模型；每个品牌的 Key 独立保存在本机 Keychain。")
                    .font(Typography.detail)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("评分模型") {
                    Picker("品牌", selection: selectedProviderID) {
                        ForEach(availableProviders) { provider in
                            Text(provider.displayName)
                                .tag(provider)
                        }
                    }
                    .disabled(isConfigurationLocked)
                    .accessibilityIdentifier("ai-settings.provider")

                    Picker("模型", selection: $selectedModelID) {
                        ForEach(providerModels) { model in
                            Text(model.displayName)
                                .tag(model.id)
                        }
                    }
                    .disabled(isConfigurationLocked)
                    .accessibilityIdentifier("ai-settings.model")

                    LabeledContent("API 模型 ID") {
                        Text(selectedModel.apiModelID)
                            .font(Typography.code)
                            .textSelection(.enabled)
                    }

                    LabeledContent("接口") {
                        Text(selectedModel.endpointHost)
                            .font(Typography.code)
                            .textSelection(.enabled)
                    }

                    if isConfigurationLocked {
                        Text("当前 AI 任务已锁定模型与预览尺寸；停止任务后可调整。")
                            .font(Typography.detail)
                            .foregroundStyle(.secondary)
                    }
                }

                if supportsModelDiscovery {
                    Section("更多模型") {
                        if isAdditionalModelSelected {
                            customField("其他 API 模型 ID") {
                                TextField(
                                    "",
                                    text: additionalModelIDBinding
                                )
                                .labelsHidden()
                                .font(Typography.code)
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("其他 API 模型 ID")
                            .accessibilityIdentifier(
                                "ai-settings.additional-model-id"
                            )

                            customField("显示名称（可选）") {
                                TextField(
                                    "",
                                    text: additionalDisplayNameBinding
                                )
                                .labelsHidden()
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("显示名称（可选）")
                            .accessibilityIdentifier(
                                "ai-settings.additional-display-name"
                            )

                            Button("使用此模型 ID") {
                                saveAdditionalModelConfiguration()
                            }
                            .disabled(
                                providerAdditionalConfiguration
                                    .modelID(
                                        for: selectedModel.providerID
                                    )
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    )
                                    .isEmpty
                            )
                            .accessibilityIdentifier(
                                "ai-settings.save-additional-model"
                            )
                        }

                        HStack {
                            Button {
                                discoverAccountModels()
                            } label: {
                                Label(
                                    isDiscoveringModels
                                        ? String(localized: "正在刷新")
                                        : String(localized: "刷新账号模型"),
                                    systemImage: "arrow.clockwise"
                                )
                            }
                            .disabled(
                                isDiscoveringModels
                                    || isVerifyingConnection
                            )
                            .accessibilityIdentifier(
                                "ai-settings.discover-models"
                            )

                            if !discoveredModels.isEmpty {
                                Menu("从账号模型选择") {
                                    ForEach(discoveredModels) { model in
                                        Button(model.displayName) {
                                            selectDiscoveredModel(model)
                                        }
                                    }
                                }
                                .accessibilityIdentifier(
                                    "ai-settings.discovered-models"
                                )
                            }
                        }

                        Text("账号模型列表只用于选择候选；图片输入和评分格式仍需点击验证后确认。")
                            .font(Typography.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                    .disabled(isConfigurationLocked)
                }

                if selectedModelID == .customOpenAICompatible {
                    Section("自定义 OpenAI-compatible") {
                        customField("显示名称") {
                            TextField("", text: $customDisplayName)
                                .labelsHidden()
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("显示名称")
                        .accessibilityIdentifier(
                            "ai-settings.custom-display-name"
                        )

                        customField("完整 Chat Completions endpoint") {
                            TextField("", text: $customEndpoint)
                                .labelsHidden()
                                .font(Typography.code)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(
                            "完整 Chat Completions endpoint"
                        )
                        .accessibilityIdentifier(
                            "ai-settings.custom-endpoint"
                        )

                        customField("API 模型 ID") {
                            TextField("", text: $customModelID)
                                .labelsHidden()
                                .font(Typography.code)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("API 模型 ID")
                        .accessibilityIdentifier(
                            "ai-settings.custom-model-id"
                        )

                        Text(
                            customConfiguration.isReady
                                ? String(localized: "兼容配置有效；首次 AI评分会验证服务实际是否支持图片和 JSON 输出。")
                                : String(localized: "请输入完整的 /chat/completions 地址和模型 ID。远程地址必须使用 HTTPS；HTTP 仅允许本机回环地址。")
                        )
                        .font(Typography.detail)
                        .foregroundStyle(
                            customConfiguration.isReady
                                ? Color.secondary
                                : Color.orange
                        )
                        .fixedSize(horizontal: false, vertical: true)

                        Button("保存兼容配置") {
                            saveCustomConfiguration()
                        }
                        .disabled(
                            !customConfiguration.isReady
                                || isConfigurationLocked
                        )
                        .accessibilityIdentifier(
                            "ai-settings.save-custom-configuration"
                        )
                    }
                    .disabled(isConfigurationLocked)
                }

                Section("评分图片尺寸") {
                    Picker("尺寸", selection: $selectedPreviewSize) {
                        ForEach(AIReviewPreviewSize.allCases) { size in
                            Text(size.title)
                                .tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isConfigurationLocked)
                    .accessibilityIdentifier("ai-settings.preview-size")
                    .accessibilityLabel("评分图片尺寸")
                    .accessibilityValue(selectedPreviewSize.displayName)

                    LabeledContent("当前发送尺寸") {
                        Text(selectedPreviewSize.displayName)
                            .font(Typography.rowLabelActive)
                    }

                    Text(selectedPreviewSize.guidance)
                        .font(Typography.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(
                        "更大的预览可能提高细节识别，也会增加上传量、等待时间和供应商费用。",
                        systemImage: "info.circle"
                    )
                    .font(Typography.detail)
                    .foregroundStyle(.secondary)
                }

                Section("\(selectedModel.providerID.displayName) API Key") {
                    SecureField(
                        "API Key",
                        text: $apiKey
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("ai-settings.api-key")

                    Text(
                        hasSavedKey
                            ? (
                                isSelectedModelVerified
                                    ? String(localized: "此品牌的 Key 已保存，当前模型连接已验证。")
                                    : String(localized: "此品牌的 Key 已保存，但当前模型尚未验证。")
                            )
                            : String(localized: "此供应商尚未保存 Key。")
                    )
                    .font(Typography.detail)
                    .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            verifyAndSaveKey()
                        } label: {
                            if isVerifyingConnection {
                                Label(
                                    "正在验证",
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                            } else {
                                Label(
                                    "验证并保存",
                                    systemImage: "checkmark.shield"
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            isVerifyingConnection
                                || AIProviderKeyStore.normalizedKey(
                                    from: apiKey
                                ).count < 12
                                || !selectedModel.isReady
                        )
                        .accessibilityIdentifier(
                            "ai-settings.verify-and-save-key"
                        )

                        if hasSavedKey {
                            Button("验证已保存的 Key") {
                                verifySavedKey()
                            }
                            .disabled(isVerifyingConnection)
                            .accessibilityIdentifier(
                                "ai-settings.verify-saved-key"
                            )

                            Button("删除此供应商的 Key", role: .destructive) {
                                deleteKey()
                            }
                            .accessibilityIdentifier("ai-settings.delete-key")
                        }
                    }
                    Text("验证会使用 1 张内置测试图调用当前模型，可能产生少量供应商费用；验证成功后才保存新 Key。")
                        .font(Typography.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(Typography.detail)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isVerifyingConnection)
            }
        }
        .padding(24)
        .frame(
            width: selectedModelID == .customOpenAICompatible ? 820 : 760,
            height: selectedModelID == .customOpenAICompatible
                || isAdditionalModelSelected
                ? 820
                : (supportsModelDiscovery ? 760 : 680)
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadCustomConfiguration()
            providerAdditionalConfiguration =
                ProviderAdditionalModelConfigurationStore.load()
            refreshKeyState()
        }
        .onChange(of: selectedModelID) { _, _ in
            apiKey = ""
            statusMessage = nil
            discoveredModels = []
            refreshKeyState()
        }
        .accessibilityIdentifier("ai-settings")
    }

    private func refreshKeyState() {
        hasSavedKey = AIProviderKeyStore.hasSavedKey(
            for: selectedModel.providerID
        )
        isSelectedModelVerified =
            AIModelVerificationStore.isVerified(selectedModel)
    }

    private var additionalModelIDBinding: Binding<String> {
        Binding(
            get: {
                providerAdditionalConfiguration.modelID(
                    for: selectedModel.providerID
                )
            },
            set: { newValue in
                updateAdditionalConfiguration(modelID: newValue)
            }
        )
    }

    private var additionalDisplayNameBinding: Binding<String> {
        Binding(
            get: {
                providerAdditionalConfiguration.configuredDisplayName(
                    for: selectedModel.providerID
                )
            },
            set: { newValue in
                updateAdditionalConfiguration(displayName: newValue)
            }
        )
    }

    private func updateAdditionalConfiguration(
        modelID: String? = nil,
        displayName: String? = nil
    ) {
        let providerID = selectedModel.providerID
        var updated = providerAdditionalConfiguration
        updated.set(
            providerID: providerID,
            modelID: modelID
                ?? updated.modelID(for: providerID),
            displayName: displayName
                ?? updated.configuredDisplayName(for: providerID)
        )
        providerAdditionalConfiguration = updated
    }

    private func saveAdditionalModelConfiguration() {
        let providerID = selectedModel.providerID
        guard providerID == .openAI || providerID == .anthropic,
              !providerAdditionalConfiguration
                .modelID(for: providerID).isEmpty else {
            statusMessage = String(
                localized: "请输入要使用的 API 模型 ID。"
            )
            return
        }
        ProviderAdditionalModelConfigurationStore.save(
            providerAdditionalConfiguration
        )
        selectedModelID = providerID == .openAI
            ? .openAIOther
            : .anthropicOther
        statusMessage = String(
            localized: "已保存\(providerID.displayName)其他模型 ID；请继续验证图片评分。"
        )
        refreshKeyState()
        didChangeConfiguration()
    }

    private func discoverAccountModels() {
        guard !isDiscoveringModels else { return }
        let providerID = selectedModel.providerID
        let enteredKey = AIProviderKeyStore.normalizedKey(from: apiKey)
        let discoveryKey: String
        if enteredKey.count >= 12 {
            discoveryKey = enteredKey
        } else {
            do {
                guard let savedKey = try AIProviderKeyStore.read(
                    for: providerID
                ) else {
                    throw AIProviderKeyStoreError.unableToRead
                }
                discoveryKey = savedKey
            } catch {
                statusMessage = String(
                    localized: "请输入 API Key，或先保存该品牌的 Key。"
                )
                return
            }
        }

        isDiscoveringModels = true
        discoveredModels = []
        statusMessage = String(
            localized: "正在刷新\(providerID.displayName)账号模型…"
        )
        Task {
            do {
                let models = try await AIModelDiscoveryService()
                    .discover(
                        providerID: providerID,
                        apiKey: discoveryKey
                    )
                discoveredModels = models
                statusMessage = models.isEmpty
                    ? String(localized: "账号未返回可用于通用图片理解的候选模型。")
                    : String(
                        localized:
                            "发现 \(models.count) 个候选模型；选择后仍需图片验证。"
                    )
            } catch {
                statusMessage = String(
                    localized: "刷新模型失败：\(error.localizedDescription)"
                )
            }
            isDiscoveringModels = false
        }
    }

    private func selectDiscoveredModel(_ model: DiscoveredAIModel) {
        var updated = providerAdditionalConfiguration
        updated.set(
            providerID: model.providerID,
            modelID: model.apiModelID,
            displayName: model.displayName
        )
        providerAdditionalConfiguration = updated
        ProviderAdditionalModelConfigurationStore.save(updated)
        selectedModelID = model.providerID == .openAI
            ? .openAIOther
            : .anthropicOther
        statusMessage = String(
            localized: "已选择\(model.displayName)；请继续验证图片评分。"
        )
        refreshKeyState()
        didChangeConfiguration()
    }

    private func customField<Content: View>(
        _ title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Typography.detail)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func loadCustomConfiguration() {
        let configuration
            = CustomOpenAICompatibleConfigurationStore.load()
        customDisplayName = configuration.displayName
        customEndpoint = configuration.endpointString
        customModelID = configuration.apiModelID
    }

    private func saveCustomConfiguration() {
        guard customConfiguration.isReady else {
            statusMessage = String(localized: "自定义兼容配置无效，未保存。")
            return
        }
        CustomOpenAICompatibleConfigurationStore.save(
            customConfiguration
        )
        statusMessage = String(localized: "已保存自定义兼容接口和模型 ID。")
        didChangeConfiguration()
    }

    private func verifyAndSaveKey() {
        let normalizedKey = AIProviderKeyStore.normalizedKey(from: apiKey)
        guard normalizedKey.count >= 12 else {
            statusMessage = AIProviderKeyStoreError.invalidKey
                .localizedDescription
            return
        }
        verify(
            apiKey: normalizedKey,
            saveAfterSuccess: true
        )
    }

    private func verifySavedKey() {
        do {
            guard let savedKey = try AIProviderKeyStore.read(
                for: selectedModel.providerID
            ) else {
                throw AIProviderKeyStoreError.unableToRead
            }
            verify(apiKey: savedKey, saveAfterSuccess: false)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func verify(
        apiKey: String,
        saveAfterSuccess: Bool
    ) {
        guard !isVerifyingConnection else { return }
        if selectedModelID == .customOpenAICompatible {
            guard customConfiguration.isReady else {
                statusMessage = String(
                    localized: "自定义兼容配置无效，未发送请求。"
                )
                return
            }
            CustomOpenAICompatibleConfigurationStore.save(
                customConfiguration
            )
        }
        if isAdditionalModelSelected {
            guard selectedModel.isReady else {
                statusMessage = String(
                    localized: "请输入要使用的 API 模型 ID。"
                )
                return
            }
            ProviderAdditionalModelConfigurationStore.save(
                providerAdditionalConfiguration
            )
        }

        let model = selectedModel
        isVerifyingConnection = true
        statusMessage = String(
            localized: "正在验证\(model.providerAndModelDisplayName)…"
        )

        Task {
            do {
                try await AIModelConnectionVerifier().verify(
                    model: model,
                    apiKey: apiKey,
                    previewSize: selectedPreviewSize
                )
                if saveAfterSuccess {
                    try AIProviderKeyStore.save(
                        apiKey,
                        for: model.providerID
                    )
                    AIModelVerificationStore.clear(
                        providerID: model.providerID
                    )
                    self.apiKey = ""
                    hasSavedKey = true
                }
                AIModelVerificationStore.markVerified(model)
                isSelectedModelVerified = true
                statusMessage = String(
                    localized: "\(model.providerAndModelDisplayName)连接成功；图片输入和评分结果均已验证。"
                )
                didChangeConfiguration()
            } catch {
                statusMessage = String(
                    localized: "连接验证失败：\(error.localizedDescription)"
                )
            }
            isVerifyingConnection = false
        }
    }

    private func deleteKey() {
        do {
            try AIProviderKeyStore.delete(for: selectedModel.providerID)
            AIModelVerificationStore.clear(
                providerID: selectedModel.providerID
            )
            hasSavedKey = false
            isSelectedModelVerified = false
            statusMessage = String(localized: "已从此 Mac 的 Keychain 删除\(selectedModel.providerID.displayName) API Key。")
            didChangeConfiguration()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
