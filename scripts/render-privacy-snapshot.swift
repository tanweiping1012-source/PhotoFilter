import AppKit
import SwiftUI

@main
struct PrivacySnapshotRenderer {
    @MainActor
    static func main() throws {
        let outputPath = CommandLine.arguments.dropFirst().first ?? "/tmp/photo-curator-privacy.png"
        let size = NSSize(width: 640, height: 680)
        let hostingView = NSHostingView(rootView: PrivacyInformationView())
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SnapshotError.cannotCreateBitmap
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.cannotEncodePNG
        }
        try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print(outputPath)
    }
}

private enum SnapshotError: Error {
    case cannotCreateBitmap
    case cannotEncodePNG
}
