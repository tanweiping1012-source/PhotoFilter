import AppKit
import Foundation
import SwiftUI

@main
struct PhotoPreviewSnapshotRenderer {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count >= 4 else {
            throw SnapshotError.missingArguments
        }
        let resourceDirectory = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let locale = Locale(identifier: CommandLine.arguments[3])
        let state = CommandLine.arguments.count > 4
            ? CommandLine.arguments[4]
            : "score"
        let renderDelay = CommandLine.arguments.count > 5
            ? Double(CommandLine.arguments[5]) ?? 2
            : 2
        let viewModel = PhotoLibraryViewModel(
            projectStore: EmptyProjectStore(),
            bookmarkAccess: EmptyBookmarkAccess(),
            apiKeyConfigurationCheck: { _ in
                fatalError("Preview snapshot must not read Keychain state.")
            },
            launchesInDemoMode: true,
            demoResourceDirectory: resourceDirectory
        )
        if state == "keep" {
            viewModel.curationScope = .people
            viewModel.recordDemoPhotoPreviewOpened()
        } else {
            viewModel.curationScope = .people
            viewModel.completeDemoAIScoringImmediately()
            viewModel.curationScope = .scenery
        }
        let size = NSSize(width: 960, height: 680)
        let rootView = PhotoPreviewView(
            photoIDs: viewModel.photos.map(\.id)
        )
        .environmentObject(viewModel)
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

        let deadline = Date().addingTimeInterval(renderDelay)
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

private enum SnapshotError: Error {
    case missingArguments
    case cannotCreateBitmap
    case cannotEncodePNG
}
