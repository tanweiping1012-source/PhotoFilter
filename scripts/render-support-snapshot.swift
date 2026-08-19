import AppKit
import Foundation
import SwiftUI

@main
struct SupportSnapshotRenderer {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else {
            throw SnapshotError.missingArguments
        }
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let locale = Locale(identifier: CommandLine.arguments[2])
        let size = NSSize(width: 560, height: 520)
        let rootView = SupportInformationView(isDemoModeActive: false)
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
