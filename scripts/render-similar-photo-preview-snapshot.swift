import AppKit
import Foundation
import SwiftUI

@main
struct SimilarPhotoPreviewSnapshotRenderer {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else {
            throw SnapshotError.missingArguments
        }
        let resourceDirectory = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "photo-curator-similar-preview-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourcePhoto = resourceDirectory.appendingPathComponent(
            DemoModeLibrary.filenames[0]
        )
        for index in 1...3 {
            try FileManager.default.copyItem(
                at: sourcePhoto,
                to: temporaryDirectory.appendingPathComponent(
                    "similar-\(index).jpg"
                )
            )
        }

        let viewModel = PhotoLibraryViewModel(
            projectStore: EmptyProjectStore(),
            bookmarkAccess: EmptyBookmarkAccess(),
            apiKeyConfigurationCheck: { _ in false },
            launchesInDemoMode: false
        )
        viewModel.scan(folder: temporaryDirectory)
        let analysisDeadline = Date().addingTimeInterval(5)
        while Date() < analysisDeadline,
              (
                  viewModel.photos.count != 3
                      || viewModel.isScanning
                      || viewModel.isAnalyzing
              ) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard viewModel.photos.count == 3,
              !viewModel.isAnalyzing,
              viewModel.photos.allSatisfy({
                  $0.similarityGroup?.count == 3
              }) else {
            throw SnapshotError.analysisFailed
        }
        let size = NSSize(width: 960, height: 680)
        let rootView = PhotoPreviewView(
            photoIDs: viewModel.photos.map(\.id)
        )
            .environmentObject(viewModel)
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

        let deadline = Date().addingTimeInterval(2)
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
    case analysisFailed
    case cannotCreateBitmap
    case cannotEncodePNG
}
