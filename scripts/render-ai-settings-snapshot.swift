import AppKit
import Foundation
import SwiftUI

@main
struct AISettingsSnapshotRenderer {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count >= 4 else {
            throw SnapshotError.missingArguments
        }
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let locale = Locale(identifier: CommandLine.arguments[2])
        let mode = CommandLine.arguments[3]
        let isCustom = mode == "custom"
        let isAdditional = mode == "openai-other"
            || mode == "anthropic-other"
        let hasDiscovery = mode == "openai" || mode == "anthropic"
        let size = NSSize(
            width: isCustom ? 820 : 760,
            height: isCustom || isAdditional
                ? 820
                : (hasDiscovery ? 760 : 680)
        )
        if isCustom {
            CustomOpenAICompatibleConfigurationStore.save(
                CustomOpenAICompatibleConfiguration(
                    displayName: "My Vision Gateway",
                    endpointString: "https://gateway.example.com/v1/chat/completions",
                    apiModelID: "vision-model"
                )
            )
        }
        if mode == "openai-other" {
            var configuration =
                ProviderAdditionalModelConfiguration.empty
            configuration.set(
                providerID: .openAI,
                modelID: "gpt-future-vision",
                displayName: "GPT Future Vision"
            )
            ProviderAdditionalModelConfigurationStore.save(
                configuration
            )
        } else if mode == "anthropic-other" {
            var configuration =
                ProviderAdditionalModelConfiguration.empty
            configuration.set(
                providerID: .anthropic,
                modelID: "claude-future-vision",
                displayName: "Claude Future Vision"
            )
            ProviderAdditionalModelConfigurationStore.save(
                configuration
            )
        }
        var modelID: AIModelID
        switch mode {
        case "custom":
            modelID = .customOpenAICompatible
        case "openai":
            modelID = .openAIGPT56Sol
        case "openai-other":
            modelID = .openAIOther
        case "anthropic":
            modelID = .anthropicClaudeFable5
        case "anthropic-other":
            modelID = .anthropicOther
        default:
            modelID = .googleGemini37Flash
        }
        var previewSize = AIReviewPreviewSize.medium
        let modelBinding = Binding(
            get: { modelID },
            set: { modelID = $0 }
        )
        let previewSizeBinding = Binding(
            get: { previewSize },
            set: { previewSize = $0 }
        )
        let rootView = AISettingsView(
            selectedModelID: modelBinding,
            selectedPreviewSize: previewSizeBinding,
            isConfigurationLocked: false,
            didChangeConfiguration: {}
        )
        .environment(\.locale, locale)
        .frame(width: size.width, height: size.height)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.bounds,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hostingView.layoutSubtreeIfNeeded()
        }

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            throw SnapshotError.cannotCreateBitmap
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(
            using: .png,
            properties: [:]
        ) else {
            throw SnapshotError.cannotEncodePNG
        }
        try pngData.write(to: outputURL, options: .atomic)
        window.close()
        print(outputURL.path)
    }
}

private enum SnapshotError: Error {
    case missingArguments
    case cannotCreateBitmap
    case cannotEncodePNG
}
