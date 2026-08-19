import AppKit
import Foundation

private let masterSize = 1024
private let outputSizes = [16, 32, 64, 128, 256, 512, 1024]

@main
struct AppIconGenerator {
    static func main() throws {
        let outputDirectory = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().first
                ?? "Resources/Assets.xcassets/AppIcon.appiconset",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let masterImage = drawMasterIcon()
        for size in outputSizes {
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: size,
                pixelsHigh: size,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw AppIconError.cannotEncodePNG
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            masterImage.draw(
                in: NSRect(x: 0, y: 0, width: size, height: size),
                from: NSRect(x: 0, y: 0, width: masterSize, height: masterSize),
                operation: .copy,
                fraction: 1
            )
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()

            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw AppIconError.cannotEncodePNG
            }
            try png.write(
                to: outputDirectory.appendingPathComponent("app-icon-\(size).png"),
                options: .atomic
            )
        }
        print("Generated \(outputSizes.count) AppIcon images at \(outputDirectory.path)")
    }
}

private enum AppIconError: Error {
    case cannotEncodePNG
}

private func drawMasterIcon() -> NSImage {
    let size = CGFloat(masterSize)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.shouldAntialias = true

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let iconRect = NSRect(x: 72, y: 72, width: 880, height: 880)
    let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 196, yRadius: 196)
    NSColor(calibratedRed: 0.08, green: 0.43, blue: 0.45, alpha: 1).setFill()
    iconPath.fill()

    let rearPhoto = NSBezierPath(
        roundedRect: NSRect(x: 206, y: 306, width: 592, height: 456),
        xRadius: 58,
        yRadius: 58
    )
    NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 0.28).setFill()
    rearPhoto.fill()

    let photoRect = NSRect(x: 166, y: 262, width: 618, height: 486)
    let photoPath = NSBezierPath(roundedRect: photoRect, xRadius: 62, yRadius: 62)
    NSColor.white.setFill()
    photoPath.fill()

    NSGraphicsContext.saveGraphicsState()
    let imageRect = NSRect(x: 198, y: 294, width: 554, height: 422)
    let clipPath = NSBezierPath(roundedRect: imageRect, xRadius: 38, yRadius: 38)
    clipPath.addClip()

    NSColor(calibratedRed: 0.76, green: 0.91, blue: 0.91, alpha: 1).setFill()
    imageRect.fill()
    drawCircle(
        color: NSColor(calibratedRed: 0.96, green: 0.69, blue: 0.23, alpha: 1),
        rect: NSRect(x: 574, y: 548, width: 104, height: 104)
    )
    drawPolygon(
        [
            NSPoint(x: 198, y: 294),
            NSPoint(x: 198, y: 470),
            NSPoint(x: 370, y: 620),
            NSPoint(x: 524, y: 454),
            NSPoint(x: 752, y: 648),
            NSPoint(x: 752, y: 294),
        ],
        color: NSColor(calibratedRed: 0.91, green: 0.32, blue: 0.27, alpha: 1)
    )
    drawPolygon(
        [
            NSPoint(x: 198, y: 294),
            NSPoint(x: 198, y: 402),
            NSPoint(x: 360, y: 494),
            NSPoint(x: 470, y: 410),
            NSPoint(x: 598, y: 482),
            NSPoint(x: 752, y: 362),
            NSPoint(x: 752, y: 294),
        ],
        color: NSColor(calibratedRed: 0.10, green: 0.33, blue: 0.25, alpha: 1)
    )
    NSGraphicsContext.restoreGraphicsState()

    let badgeRect = NSRect(x: 594, y: 170, width: 268, height: 268)
    let badgePath = NSBezierPath(ovalIn: badgeRect)
    NSColor(calibratedRed: 0.96, green: 0.70, blue: 0.24, alpha: 1).setFill()
    badgePath.fill()

    let checkmark = NSBezierPath()
    checkmark.move(to: NSPoint(x: 654, y: 298))
    checkmark.line(to: NSPoint(x: 712, y: 244))
    checkmark.line(to: NSPoint(x: 812, y: 350))
    checkmark.lineWidth = 40
    checkmark.lineCapStyle = .round
    checkmark.lineJoinStyle = .round
    NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.14, alpha: 1).setStroke()
    checkmark.stroke()

    image.unlockFocus()
    return image
}

private func drawCircle(color: NSColor, rect: NSRect) {
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
}

private func drawPolygon(_ points: [NSPoint], color: NSColor) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    points.dropFirst().forEach { path.line(to: $0) }
    path.close()
    color.setFill()
    path.fill()
}
