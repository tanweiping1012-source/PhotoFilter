import Foundation
import XCTest

@testable import PhotoCurator

final class AIModelCatalogTests: XCTestCase {
    func testCatalogOnlyExposesImplementedImageModels() {
        XCTAssertEqual(
            AIModelCatalog.availableProviders,
            [
                .volcengineArk,
                .miniMax,
                .openAI,
                .anthropic,
                .googleGemini,
                .alibabaModelStudio,
                .xAI,
                .moonshotKimi,
                .zhipuGLM,
                .tencentHunyuan,
                .customOpenAICompatible,
            ]
        )
        XCTAssertTrue(
            AIModelCatalog.availableModels.allSatisfy(\.supportsImageInput)
        )
        XCTAssertTrue(
            AIModelCatalog.availableModels.filter(\.isReady).allSatisfy {
                !$0.apiModelID.isEmpty
                    && $0.endpoint.scheme == "https"
                    && $0.endpoint.host != nil
            }
        )
        XCTAssertEqual(
            AIModelCatalog.models(for: .openAI).map(\.id),
            [
                .openAIGPT56Sol,
                .openAIGPT56Terra,
                .openAIGPT56Luna,
                .openAIGPT55,
                .openAIGPT54,
                .openAIGPT54Mini,
                .openAIGPT54Nano,
                .openAIOther,
            ]
        )
        XCTAssertEqual(
            AIModelCatalog.models(for: .anthropic).map(\.id),
            [
                .anthropicClaudeFable5,
                .anthropicClaudeOpus5,
                .anthropicClaudeOpus48,
                .anthropicClaudeOpus47,
                .anthropicClaudeOpus46,
                .anthropicClaudeOpus45,
                .anthropicClaudeSonnet5,
                .anthropicClaudeSonnet46,
                .anthropicClaudeSonnet45,
                .anthropicClaudeHaiku45,
                .anthropicOther,
            ]
        )
        XCTAssertEqual(
            AIModelCatalog.models(for: .moonshotKimi).map(\.id),
            [.moonshotKimiK3, .moonshotKimiK26, .moonshotKimiK25]
        )
        XCTAssertEqual(
            AIModelCatalog.models(for: .zhipuGLM).map(\.id),
            [.zhipuGLM46V, .zhipuGLM46VFlashX, .zhipuGLM46VFlash]
        )
        XCTAssertEqual(
            AIModelCatalog.model(for: .miniMaxM3).apiModelID,
            "MiniMax-M3"
        )
        XCTAssertEqual(
            AIModelCatalog.model(for: .miniMaxM3).endpoint.absoluteString,
            "https://api.minimaxi.com/v1/chat/completions"
        )
        XCTAssertEqual(
            AIModelCatalog.model(for: .openAIGPT54Mini).protocolID,
            .openAICompatibleChatCompletions
        )
        XCTAssertEqual(
            AIModelCatalog.model(for: .anthropicClaudeSonnet5).protocolID,
            .anthropicMessages
        )
        XCTAssertFalse(
            AIModelCatalog.model(for: .customOpenAICompatible).isReady
        )
        XCTAssertEqual(
            AIModelCatalog.defaultModelID(for: .googleGemini),
            .googleGemini31ProPreview
        )
    }

    func testSelectionStoreDefaultsAndRoundTripsKnownModel() throws {
        let suiteName = "photo-curator-model-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults.")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            AIModelSelectionStore.load(defaults: defaults),
            .doubaoSeed20Lite
        )

        AIModelSelectionStore.save(.miniMaxM3, defaults: defaults)

        XCTAssertEqual(
            AIModelSelectionStore.load(defaults: defaults),
            .miniMaxM3
        )
    }

    func testPreviewSizesHaveStablePixelsAndProviderDetail() {
        XCTAssertEqual(
            AIReviewPreviewSize.allCases.map(\.maximumPixelSize),
            [512, 1_024, 1_536]
        )
        XCTAssertEqual(
            AIReviewPreviewSize.allCases.map(\.miniMaxDetail),
            ["low", "default", "high"]
        )
    }

    func testPreviewSizeStoreDefaultsToSmallAndRoundTrips() throws {
        let suiteName = "photo-curator-preview-size-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults.")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            AIReviewPreviewSizeStore.load(defaults: defaults),
            .small
        )

        AIReviewPreviewSizeStore.save(.large, defaults: defaults)

        XCTAssertEqual(
            AIReviewPreviewSizeStore.load(defaults: defaults),
            .large
        )
    }

    func testProviderKeychainServicesAreIsolatedAndArkNameIsStable() {
        let bundleID = "com.example.PhotoCurator"

        XCTAssertEqual(
            AIProviderKeyStore.serviceName(
                for: .volcengineArk,
                bundleIdentifier: bundleID
            ),
            "com.example.PhotoCurator.ark-api-key"
        )
        XCTAssertEqual(
            AIProviderKeyStore.serviceName(
                for: .miniMax,
                bundleIdentifier: bundleID
            ),
            "com.example.PhotoCurator.ai-api-key.minimax"
        )
        let services = AIProviderID.allCases.map {
            AIProviderKeyStore.serviceName(
                for: $0,
                bundleIdentifier: bundleID
            )
        }
        XCTAssertEqual(Set(services).count, AIProviderID.allCases.count)
    }

    func testCustomCompatibleConfigurationValidatesAndRoundTrips() throws {
        let valid = CustomOpenAICompatibleConfiguration(
            displayName: "My Vision",
            endpointString: "https://gateway.example.com/v1/chat/completions",
            apiModelID: "vision-model"
        )
        XCTAssertTrue(valid.isReady)
        XCTAssertEqual(
            valid.modelDescriptor.endpointHost,
            "gateway.example.com"
        )
        XCTAssertTrue(
            CustomOpenAICompatibleConfiguration(
                displayName: "Local",
                endpointString: "http://127.0.0.1:11434/v1/chat/completions",
                apiModelID: "llava"
            ).isReady
        )
        XCTAssertFalse(
            CustomOpenAICompatibleConfiguration(
                displayName: "Unsafe",
                endpointString: "http://remote.example.com/v1/chat/completions",
                apiModelID: "vision"
            ).isReady
        )
        XCTAssertFalse(
            CustomOpenAICompatibleConfiguration(
                displayName: "Leaky",
                endpointString: "https://user:pass@example.com/v1/chat/completions?key=secret",
                apiModelID: "vision"
            ).isReady
        )

        let suiteName = "photo-curator-custom-model-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CustomOpenAICompatibleConfigurationStore.save(
            valid,
            defaults: defaults
        )
        XCTAssertEqual(
            CustomOpenAICompatibleConfigurationStore.load(
                defaults: defaults
            ),
            valid
        )
    }

    @MainActor
    func testViewModelChecksSelectedProviderOnly() {
        var checkedProviders: [AIProviderID] = []
        let viewModel = PhotoLibraryViewModel(
            projectStore: EmptyProjectStore(),
            bookmarkAccess: EmptyBookmarkAccess(),
            initialAIModelID: .miniMaxM3,
            apiKeyConfigurationCheck: { providerID in
                checkedProviders.append(providerID)
                return providerID == .miniMax
            },
            modelVerificationCheck: { model in
                model.id == .miniMaxM3
            }
        )

        viewModel.refreshAIConfiguration()

        XCTAssertEqual(checkedProviders, [.miniMax])
        XCTAssertTrue(viewModel.isAIModelKeyConfigured)

        viewModel.selectedAIModelID = AIModelID.doubaoSeed20Lite

        XCTAssertEqual(checkedProviders, [.miniMax, .volcengineArk])
        XCTAssertFalse(viewModel.isAIModelKeyConfigured)
    }

    func testModelVerificationIsPerModelAndClearsWithProvider()
        throws {
        let suiteName =
            "photo-curator-model-verification-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let mini = AIModelCatalog.model(for: .openAIGPT54Mini)
        let flagship = AIModelCatalog.model(for: .openAIGPT54)
        AIModelVerificationStore.markVerified(
            mini,
            defaults: defaults
        )

        XCTAssertTrue(
            AIModelVerificationStore.isVerified(
                mini,
                defaults: defaults
            )
        )
        XCTAssertFalse(
            AIModelVerificationStore.isVerified(
                flagship,
                defaults: defaults
            )
        )

        AIModelVerificationStore.clear(
            providerID: .openAI,
            defaults: defaults
        )

        XCTAssertFalse(
            AIModelVerificationStore.isVerified(
                mini,
                defaults: defaults
            )
        )
    }

    func testAdditionalProviderModelUsesRealModelIDIdentity()
        throws {
        var configuration = ProviderAdditionalModelConfiguration.empty
        configuration.set(
            providerID: .openAI,
            modelID: "gpt-future-vision",
            displayName: "Future Vision"
        )
        let model = configuration.modelDescriptor(for: .openAI)

        XCTAssertEqual(model.id, .openAIOther)
        XCTAssertEqual(model.apiModelID, "gpt-future-vision")
        XCTAssertEqual(model.displayName, "Future Vision")
        XCTAssertTrue(model.isReady)
        XCTAssertEqual(
            AIModelVerificationStore.verificationIdentity(for: model),
            "openai|gpt-future-vision"
        )
        var changedConfiguration = configuration
        changedConfiguration.set(
            providerID: .openAI,
            modelID: "gpt-another-vision",
            displayName: "Another Vision"
        )

        let suiteName =
            "photo-curator-additional-model-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        ProviderAdditionalModelConfigurationStore.save(
            configuration,
            defaults: defaults
        )
        AIModelVerificationStore.markVerified(model, defaults: defaults)
        XCTAssertFalse(
            AIModelVerificationStore.isVerified(
                changedConfiguration.modelDescriptor(for: .openAI),
                defaults: defaults
            )
        )
        XCTAssertEqual(
            ProviderAdditionalModelConfigurationStore.load(
                defaults: defaults
            ),
            configuration
        )
    }
}

private final class EmptyProjectStore: PhotoProjectPersisting {
    func load() throws -> PersistedPhotoProjectCatalog? { nil }
    func save(_ catalog: PersistedPhotoProjectCatalog) throws {}
}

private final class EmptyBookmarkAccess: SecurityScopedBookmarkAccessing {
    func makeReadOnlyBookmark(for folderURL: URL) throws -> Data { Data() }

    func resolve(_ bookmarkData: Data) throws -> ResolvedProjectBookmark {
        throw ProjectPersistenceError.inaccessibleBookmark
    }

    func startAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}
