import AppKit
import Foundation
import SwiftUI

@main
struct DemoSnapshotRenderer {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count >= 7,
              let width = Double(CommandLine.arguments[3]),
              let height = Double(CommandLine.arguments[4]) else {
            throw DemoSnapshotError.missingArguments
        }
        let resourceDirectory = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let locale = Locale(identifier: CommandLine.arguments[5])
        let state = CommandLine.arguments[6]
        let viewModel = PhotoLibraryViewModel(
            projectStore: EmptyProjectStore(),
            bookmarkAccess: EmptyBookmarkAccess(),
            apiKeyConfigurationCheck: { _ in
                fatalError("Demo snapshot must not read Keychain state.")
            },
            launchesInDemoMode: true,
            demoResourceDirectory: resourceDirectory
        )
        switch state {
        case "choose-people", "guided":
            break
        case "inspect-photo":
            viewModel.curationScope = .people
        case "run-ai":
            beginPeopleCuration(viewModel)
        case "scoring":
            beginPeopleCuration(viewModel)
            viewModel.startDemoAIScoring()
        case "switch-scenery":
            beginPeopleCuration(viewModel)
            viewModel.completeDemoAIScoringImmediately()
        case "view-score", "scenery":
            beginPeopleCuration(viewModel)
            viewModel.completeDemoAIScoringImmediately()
            viewModel.curationScope = .scenery
        case "accept-results":
            advanceToAcceptResults(viewModel)
        case "export":
            advanceToAcceptResults(viewModel)
            viewModel.acceptPendingAIFinalSelection()
        case "completed":
            advanceToAcceptResults(viewModel)
            viewModel.acceptPendingAIFinalSelection()
            viewModel.recordDemoExportCompleted()
        default:
            viewModel.completeDemoAIScoringImmediately()
        }
        let size = NSSize(width: width, height: height)
        let rootView = ContentView()
            .environmentObject(viewModel)
            .environment(\.locale, locale)
            .frame(width: size.width, height: size.height)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.bounds,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)

        let deadline = Date().addingTimeInterval(
            state == "scoring" ? 1.05 : 2
        )
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hostingView.layoutSubtreeIfNeeded()
        }

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw DemoSnapshotError.cannotCreateBitmap
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw DemoSnapshotError.cannotEncodePNG
        }
        try pngData.write(to: outputURL, options: .atomic)
        window.close()
        print(outputURL.path)
    }

    @MainActor
    private static func advanceToAcceptResults(
        _ viewModel: PhotoLibraryViewModel
    ) {
        beginPeopleCuration(viewModel)
        viewModel.completeDemoAIScoringImmediately()
        viewModel.curationScope = .scenery
        viewModel.recordDemoScoreReviewFinished()
    }

    @MainActor
    private static func beginPeopleCuration(
        _ viewModel: PhotoLibraryViewModel
    ) {
        viewModel.curationScope = .people
        viewModel.recordDemoPhotoPreviewOpened()
        if let firstPhotoID = viewModel.photos.first?.id {
            viewModel.mark(photoID: firstPhotoID, as: .keep)
        }
    }
}

private final class EmptyProjectStore: PhotoProjectPersisting {
    func load() throws -> PersistedPhotoProjectCatalog? {
        nil
    }

    func save(_ catalog: PersistedPhotoProjectCatalog) throws {
        fatalError("Demo snapshot must not persist a project catalog.")
    }
}

private final class EmptyBookmarkAccess: SecurityScopedBookmarkAccessing {
    func makeReadOnlyBookmark(for folderURL: URL) throws -> Data {
        fatalError("Demo snapshot must not create a bookmark.")
    }

    func resolve(_ bookmarkData: Data) throws -> ResolvedProjectBookmark {
        fatalError("Demo snapshot must not resolve a bookmark.")
    }

    func startAccessing(_ url: URL) -> Bool {
        fatalError("Demo snapshot must not start a security-scoped resource.")
    }

    func stopAccessing(_ url: URL) {}
}

private enum DemoSnapshotError: Error {
    case missingArguments
    case cannotCreateBitmap
    case cannotEncodePNG
}
