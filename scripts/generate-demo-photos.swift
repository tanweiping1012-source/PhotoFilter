import AppKit
import Foundation

private let canvasSize = NSSize(width: 1200, height: 900)

@main
struct DemoPhotoGenerator {
    static func main() throws {
        let outputDirectory = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/DemoPhotos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let scenes: [(String, (NSRect) -> Void)] = [
            ("demo-01-coastal-road.jpg", drawCoastalRoad),
            ("demo-02-lighthouse.jpg", drawLighthouse),
            ("demo-03-forest-trail.jpg", drawForestTrail),
            ("demo-04-harbor.jpg", drawHarbor),
            ("demo-05-ocean-overlook.jpg", drawOceanOverlook),
            ("demo-06-hillside-village.jpg", drawHillsideVillage),
            ("demo-07-mountain-lake.jpg", drawMountainLake),
            ("demo-08-sunset-beach.jpg", drawSunsetBeach),
        ]

        for (filename, drawScene) in scenes {
            let image = NSImage(size: canvasSize)
            image.lockFocus()
            guard let context = NSGraphicsContext.current else {
                throw DemoAssetError.cannotCreateContext
            }
            context.imageInterpolation = .high
            let bounds = NSRect(origin: .zero, size: canvasSize)
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            drawScene(bounds)
            addFilmGrain(in: bounds)
            image.unlockFocus()

            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let data = NSBitmapImageRep(cgImage: cgImage).representation(
                    using: .jpeg,
                    properties: [.compressionFactor: 0.88]
                  ) else {
                throw DemoAssetError.cannotEncodeJPEG
            }
            try data.write(to: outputDirectory.appendingPathComponent(filename), options: .atomic)
        }

        print("\(scenes.count) demo photos generated at \(outputDirectory.path)")
    }
}

private enum DemoAssetError: Error {
    case cannotCreateContext
    case cannotEncodeJPEG
}

private func gradient(_ colors: [NSColor], in rect: NSRect, angle: CGFloat = 90) {
    NSGradient(colors: colors)?.draw(in: rect, angle: angle)
}

private func fill(_ color: NSColor, _ rect: NSRect) {
    color.setFill()
    rect.fill()
}

private func polygon(_ points: [NSPoint], color: NSColor) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.close()
    color.setFill()
    path.fill()
}

private func ellipse(_ color: NSColor, _ rect: NSRect) {
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
}

private func line(
    _ color: NSColor,
    from start: NSPoint,
    to end: NSPoint,
    width: CGFloat,
    dash: [CGFloat] = []
) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = width
    if !dash.isEmpty {
        path.setLineDash(dash, count: dash.count, phase: 0)
    }
    color.setStroke()
    path.stroke()
}

private func drawCloud(at origin: NSPoint, scale: CGFloat, alpha: CGFloat = 0.75) {
    let color = NSColor.white.withAlphaComponent(alpha)
    ellipse(color, NSRect(x: origin.x, y: origin.y, width: 150 * scale, height: 55 * scale))
    ellipse(color, NSRect(x: origin.x + 35 * scale, y: origin.y + 15 * scale, width: 80 * scale, height: 65 * scale))
    ellipse(color, NSRect(x: origin.x + 85 * scale, y: origin.y + 8 * scale, width: 90 * scale, height: 58 * scale))
}

private func drawTree(at x: CGFloat, baseY: CGFloat, scale: CGFloat, color: NSColor) {
    fill(
        NSColor(calibratedRed: 0.25, green: 0.16, blue: 0.10, alpha: 1),
        NSRect(x: x - 6 * scale, y: baseY, width: 12 * scale, height: 58 * scale)
    )
    polygon(
        [
            NSPoint(x: x, y: baseY + 145 * scale),
            NSPoint(x: x - 48 * scale, y: baseY + 42 * scale),
            NSPoint(x: x + 48 * scale, y: baseY + 42 * scale),
        ],
        color: color
    )
    polygon(
        [
            NSPoint(x: x, y: baseY + 112 * scale),
            NSPoint(x: x - 55 * scale, y: baseY + 18 * scale),
            NSPoint(x: x + 55 * scale, y: baseY + 18 * scale),
        ],
        color: color.blended(withFraction: 0.12, of: .black) ?? color
    )
}

private func drawPerson(
    at x: CGFloat,
    baseY: CGFloat,
    scale: CGFloat,
    shirt: NSColor,
    trousers: NSColor,
    skin: NSColor = NSColor(
        calibratedRed: 0.74,
        green: 0.49,
        blue: 0.34,
        alpha: 1
    ),
    facingRight: Bool = true
) {
    let direction: CGFloat = facingRight ? 1 : -1
    let head = NSRect(
        x: x - 24 * scale,
        y: baseY + 174 * scale,
        width: 48 * scale,
        height: 55 * scale
    )
    ellipse(skin, head)
    ellipse(
        NSColor(calibratedWhite: 0.12, alpha: 1),
        NSRect(
            x: head.minX - (facingRight ? 5 : -5) * scale,
            y: head.midY + 4 * scale,
            width: 46 * scale,
            height: 31 * scale
        )
    )
    polygon(
        [
            NSPoint(x: x - 38 * scale, y: baseY + 170 * scale),
            NSPoint(x: x + 35 * scale, y: baseY + 170 * scale),
            NSPoint(x: x + 48 * scale, y: baseY + 82 * scale),
            NSPoint(x: x - 46 * scale, y: baseY + 82 * scale),
        ],
        color: shirt
    )
    line(
        skin,
        from: NSPoint(
            x: x - 34 * scale,
            y: baseY + 154 * scale
        ),
        to: NSPoint(
            x: x - 64 * scale * direction,
            y: baseY + 98 * scale
        ),
        width: 14 * scale
    )
    line(
        skin,
        from: NSPoint(
            x: x + 32 * scale,
            y: baseY + 152 * scale
        ),
        to: NSPoint(
            x: x + 58 * scale * direction,
            y: baseY + 112 * scale
        ),
        width: 14 * scale
    )
    polygon(
        [
            NSPoint(x: x - 43 * scale, y: baseY + 86 * scale),
            NSPoint(x: x + 45 * scale, y: baseY + 86 * scale),
            NSPoint(x: x + 35 * scale, y: baseY + 48 * scale),
            NSPoint(x: x - 36 * scale, y: baseY + 48 * scale),
        ],
        color: trousers
    )
    line(
        trousers,
        from: NSPoint(x: x - 21 * scale, y: baseY + 55 * scale),
        to: NSPoint(x: x - 31 * scale, y: baseY),
        width: 23 * scale
    )
    line(
        trousers,
        from: NSPoint(x: x + 20 * scale, y: baseY + 55 * scale),
        to: NSPoint(x: x + 35 * scale, y: baseY),
        width: 23 * scale
    )
    line(
        NSColor(calibratedWhite: 0.08, alpha: 1),
        from: NSPoint(x: x - 43 * scale, y: baseY),
        to: NSPoint(x: x - 18 * scale, y: baseY),
        width: 12 * scale
    )
    line(
        NSColor(calibratedWhite: 0.08, alpha: 1),
        from: NSPoint(x: x + 24 * scale, y: baseY),
        to: NSPoint(x: x + 49 * scale, y: baseY),
        width: 12 * scale
    )
}

private func drawCoastalRoad(_ bounds: NSRect) {
    gradient(
        [
            NSColor(calibratedRed: 0.50, green: 0.78, blue: 0.94, alpha: 1),
            NSColor(calibratedRed: 0.90, green: 0.96, blue: 0.98, alpha: 1),
        ],
        in: NSRect(x: 0, y: 380, width: bounds.width, height: 520)
    )
    drawCloud(at: NSPoint(x: 110, y: 700), scale: 1.2)
    drawCloud(at: NSPoint(x: 760, y: 760), scale: 0.85)
    gradient(
        [
            NSColor(calibratedRed: 0.05, green: 0.42, blue: 0.62, alpha: 1),
            NSColor(calibratedRed: 0.24, green: 0.67, blue: 0.78, alpha: 1),
        ],
        in: NSRect(x: 0, y: 250, width: bounds.width, height: 260)
    )
    polygon(
        [
            NSPoint(x: 0, y: 420), NSPoint(x: 260, y: 560),
            NSPoint(x: 510, y: 470), NSPoint(x: 720, y: 585),
            NSPoint(x: 950, y: 460), NSPoint(x: 1200, y: 545),
            NSPoint(x: 1200, y: 0), NSPoint(x: 0, y: 0),
        ],
        color: NSColor(calibratedRed: 0.18, green: 0.43, blue: 0.25, alpha: 1)
    )
    polygon(
        [
            NSPoint(x: 470, y: 0), NSPoint(x: 610, y: 430),
            NSPoint(x: 750, y: 430), NSPoint(x: 1030, y: 0),
        ],
        color: NSColor(calibratedWhite: 0.18, alpha: 1)
    )
    line(.white, from: NSPoint(x: 750, y: 0), to: NSPoint(x: 681, y: 420), width: 12, dash: [38, 34])
    line(NSColor(calibratedRed: 0.88, green: 0.72, blue: 0.22, alpha: 1), from: NSPoint(x: 590, y: 0), to: NSPoint(x: 650, y: 425), width: 9)
    drawPerson(
        at: 285,
        baseY: 48,
        scale: 1.55,
        shirt: NSColor(
            calibratedRed: 0.78,
            green: 0.20,
            blue: 0.18,
            alpha: 1
        ),
        trousers: NSColor(
            calibratedRed: 0.10,
            green: 0.18,
            blue: 0.28,
            alpha: 1
        )
    )
}

private func drawLighthouse(_ bounds: NSRect) {
    gradient(
        [
            NSColor(calibratedRed: 0.30, green: 0.66, blue: 0.90, alpha: 1),
            NSColor(calibratedRed: 0.86, green: 0.94, blue: 0.98, alpha: 1),
        ],
        in: NSRect(x: 0, y: 330, width: bounds.width, height: 570)
    )
    gradient(
        [
            NSColor(calibratedRed: 0.04, green: 0.35, blue: 0.58, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.60, blue: 0.76, alpha: 1),
        ],
        in: NSRect(x: 0, y: 0, width: 720, height: 430)
    )
    polygon(
        [
            NSPoint(x: 650, y: 0), NSPoint(x: 720, y: 330),
            NSPoint(x: 900, y: 430), NSPoint(x: 1200, y: 390),
            NSPoint(x: 1200, y: 0),
        ],
        color: NSColor(calibratedRed: 0.23, green: 0.39, blue: 0.20, alpha: 1)
    )
    fill(.white, NSRect(x: 930, y: 275, width: 90, height: 300))
    polygon(
        [
            NSPoint(x: 910, y: 575), NSPoint(x: 1040, y: 575),
            NSPoint(x: 1015, y: 630), NSPoint(x: 935, y: 630),
        ],
        color: NSColor(calibratedRed: 0.70, green: 0.12, blue: 0.10, alpha: 1)
    )
    fill(NSColor(calibratedWhite: 0.12, alpha: 1), NSRect(x: 940, y: 520, width: 70, height: 48))
    line(.white.withAlphaComponent(0.75), from: NSPoint(x: 60, y: 220), to: NSPoint(x: 540, y: 250), width: 8)
    line(.white.withAlphaComponent(0.55), from: NSPoint(x: 120, y: 150), to: NSPoint(x: 610, y: 175), width: 5)
    drawPerson(
        at: 720,
        baseY: 45,
        scale: 1.20,
        shirt: NSColor(
            calibratedRed: 0.92,
            green: 0.65,
            blue: 0.18,
            alpha: 1
        ),
        trousers: NSColor(
            calibratedRed: 0.13,
            green: 0.27,
            blue: 0.38,
            alpha: 1
        )
    )
    drawPerson(
        at: 840,
        baseY: 48,
        scale: 1.12,
        shirt: NSColor(
            calibratedRed: 0.26,
            green: 0.57,
            blue: 0.66,
            alpha: 1
        ),
        trousers: NSColor(
            calibratedRed: 0.19,
            green: 0.18,
            blue: 0.24,
            alpha: 1
        ),
        facingRight: false
    )
}

private func drawForestTrail(_ bounds: NSRect) {
    gradient(
        [
            NSColor(calibratedRed: 0.42, green: 0.64, blue: 0.54, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.23, blue: 0.15, alpha: 1),
        ],
        in: bounds
    )
    for offset in stride(from: 40, through: 1160, by: 90) {
        let scale = 0.85 + CGFloat((offset / 90) % 4) * 0.08
        drawTree(
            at: CGFloat(offset),
            baseY: 220,
            scale: scale * 2.2,
            color: NSColor(calibratedRed: 0.05, green: 0.28, blue: 0.16, alpha: 1)
        )
    }
    polygon(
        [
            NSPoint(x: 390, y: 0), NSPoint(x: 565, y: 520),
            NSPoint(x: 660, y: 520), NSPoint(x: 850, y: 0),
        ],
        color: NSColor(calibratedRed: 0.53, green: 0.43, blue: 0.28, alpha: 1)
    )
    line(NSColor.white.withAlphaComponent(0.18), from: NSPoint(x: 260, y: 900), to: NSPoint(x: 520, y: 320), width: 80)
    line(NSColor.white.withAlphaComponent(0.12), from: NSPoint(x: 820, y: 900), to: NSPoint(x: 690, y: 360), width: 55)
    drawPerson(
        at: 510,
        baseY: 55,
        scale: 1.08,
        shirt: NSColor(
            calibratedRed: 0.85,
            green: 0.36,
            blue: 0.16,
            alpha: 1
        ),
        trousers: NSColor(
            calibratedRed: 0.12,
            green: 0.20,
            blue: 0.18,
            alpha: 1
        )
    )
    drawPerson(
        at: 625,
        baseY: 62,
        scale: 0.95,
        shirt: NSColor(
            calibratedRed: 0.20,
            green: 0.50,
            blue: 0.72,
            alpha: 1
        ),
        trousers: NSColor(
            calibratedRed: 0.17,
            green: 0.17,
            blue: 0.22,
            alpha: 1
        ),
        facingRight: false
    )
    drawPerson(
        at: 710,
        baseY: 70,
        scale: 0.72,
        shirt: NSColor(
            calibratedRed: 0.80,
            green: 0.68,
            blue: 0.22,
            alpha: 1
        ),
        trousers: NSColor(
            calibratedRed: 0.18,
            green: 0.24,
            blue: 0.28,
            alpha: 1
        )
    )
}

private func drawHarbor(_ bounds: NSRect) {
    gradient(
        [
            NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.29, alpha: 1),
            NSColor(calibratedRed: 0.34, green: 0.49, blue: 0.62, alpha: 1),
        ],
        in: NSRect(x: 0, y: 430, width: bounds.width, height: 470)
    )
    ellipse(NSColor(calibratedWhite: 0.95, alpha: 0.9), NSRect(x: 920, y: 720, width: 70, height: 70))
    polygon(
        [
            NSPoint(x: 0, y: 430), NSPoint(x: 230, y: 590),
            NSPoint(x: 510, y: 500), NSPoint(x: 780, y: 610),
            NSPoint(x: 1200, y: 465), NSPoint(x: 1200, y: 360),
            NSPoint(x: 0, y: 360),
        ],
        color: NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.22, alpha: 1)
    )
    gradient(
        [
            NSColor(calibratedRed: 0.05, green: 0.20, blue: 0.31, alpha: 1),
            NSColor(calibratedRed: 0.18, green: 0.38, blue: 0.48, alpha: 1),
        ],
        in: NSRect(x: 0, y: 0, width: bounds.width, height: 430)
    )
    for x in stride(from: 120, through: 1040, by: 230) {
        polygon(
            [
                NSPoint(x: CGFloat(x), y: 230), NSPoint(x: CGFloat(x + 150), y: 230),
                NSPoint(x: CGFloat(x + 125), y: 180), NSPoint(x: CGFloat(x + 25), y: 180),
            ],
            color: NSColor(calibratedRed: 0.75, green: 0.79, blue: 0.78, alpha: 1)
        )
        line(.white.withAlphaComponent(0.75), from: NSPoint(x: CGFloat(x + 75), y: 235), to: NSPoint(x: CGFloat(x + 75), y: 390), width: 5)
        line(NSColor(calibratedRed: 0.92, green: 0.70, blue: 0.30, alpha: 0.32), from: NSPoint(x: CGFloat(x + 75), y: 165), to: NSPoint(x: CGFloat(x + 75), y: 30), width: 10)
    }
    drawPerson(
        at: 165,
        baseY: 32,
        scale: 1.42,
        shirt: NSColor(
            calibratedRed: 0.72,
            green: 0.18,
            blue: 0.20,
            alpha: 1
        ),
        trousers: NSColor(
            calibratedRed: 0.10,
            green: 0.16,
            blue: 0.26,
            alpha: 1
        )
    )
}

private func drawOceanOverlook(_ bounds: NSRect) {
    gradient(
        [
            NSColor(calibratedRed: 0.55, green: 0.80, blue: 0.95, alpha: 1),
            NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.94, alpha: 1),
        ],
        in: NSRect(x: 0, y: 500, width: bounds.width, height: 400)
    )
    gradient(
        [
            NSColor(calibratedRed: 0.07, green: 0.40, blue: 0.66, alpha: 1),
            NSColor(calibratedRed: 0.26, green: 0.67, blue: 0.78, alpha: 1),
        ],
        in: NSRect(x: 0, y: 150, width: bounds.width, height: 410)
    )
    polygon(
        [
            NSPoint(x: 0, y: 0), NSPoint(x: 0, y: 380),
            NSPoint(x: 240, y: 315), NSPoint(x: 390, y: 390),
            NSPoint(x: 580, y: 240), NSPoint(x: 750, y: 275),
            NSPoint(x: 980, y: 120), NSPoint(x: 1200, y: 155),
            NSPoint(x: 1200, y: 0),
        ],
        color: NSColor(calibratedRed: 0.27, green: 0.46, blue: 0.20, alpha: 1)
    )
    line(.white.withAlphaComponent(0.65), from: NSPoint(x: 560, y: 380), to: NSPoint(x: 930, y: 345), width: 7)
}

private func drawHillsideVillage(_ bounds: NSRect) {
    gradient(
        [
            NSColor(calibratedRed: 0.44, green: 0.72, blue: 0.91, alpha: 1),
            NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.88, alpha: 1),
        ],
        in: NSRect(x: 0, y: 410, width: bounds.width, height: 490)
    )
    polygon(
        [
            NSPoint(x: 0, y: 0), NSPoint(x: 0, y: 450),
            NSPoint(x: 280, y: 580), NSPoint(x: 510, y: 470),
            NSPoint(x: 760, y: 600), NSPoint(x: 1200, y: 420),
            NSPoint(x: 1200, y: 0),
        ],
        color: NSColor(calibratedRed: 0.31, green: 0.51, blue: 0.26, alpha: 1)
    )
    let houses = [
        NSPoint(x: 170, y: 330), NSPoint(x: 350, y: 390), NSPoint(x: 510, y: 305),
        NSPoint(x: 690, y: 410), NSPoint(x: 850, y: 300), NSPoint(x: 980, y: 380),
    ]
    for (index, point) in houses.enumerated() {
        let width: CGFloat = index.isMultiple(of: 2) ? 125 : 105
        fill(
            NSColor(calibratedRed: 0.92, green: 0.86, blue: 0.70, alpha: 1),
            NSRect(x: point.x, y: point.y, width: width, height: 100)
        )
        polygon(
            [
                NSPoint(x: point.x - 10, y: point.y + 100),
                NSPoint(x: point.x + width / 2, y: point.y + 155),
                NSPoint(x: point.x + width + 10, y: point.y + 100),
            ],
            color: NSColor(calibratedRed: 0.67, green: 0.18, blue: 0.12, alpha: 1)
        )
    }
}

private func drawMountainLake(_ bounds: NSRect) {
    gradient(
        [
            NSColor(calibratedRed: 0.40, green: 0.66, blue: 0.88, alpha: 1),
            NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.94, alpha: 1),
        ],
        in: NSRect(x: 0, y: 430, width: bounds.width, height: 470)
    )
    polygon(
        [
            NSPoint(x: 0, y: 420), NSPoint(x: 240, y: 740),
            NSPoint(x: 420, y: 510), NSPoint(x: 650, y: 790),
            NSPoint(x: 830, y: 540), NSPoint(x: 1010, y: 720),
            NSPoint(x: 1200, y: 460), NSPoint(x: 1200, y: 300),
            NSPoint(x: 0, y: 300),
        ],
        color: NSColor(calibratedRed: 0.20, green: 0.31, blue: 0.32, alpha: 1)
    )
    polygon(
        [
            NSPoint(x: 515, y: 625), NSPoint(x: 650, y: 790),
            NSPoint(x: 770, y: 625), NSPoint(x: 690, y: 665),
            NSPoint(x: 620, y: 650),
        ],
        color: NSColor.white.withAlphaComponent(0.78)
    )
    gradient(
        [
            NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.55, alpha: 1),
            NSColor(calibratedRed: 0.33, green: 0.69, blue: 0.72, alpha: 1),
        ],
        in: NSRect(x: 0, y: 0, width: bounds.width, height: 430)
    )
    line(.white.withAlphaComponent(0.42), from: NSPoint(x: 100, y: 225), to: NSPoint(x: 1040, y: 225), width: 4)
    line(.white.withAlphaComponent(0.24), from: NSPoint(x: 230, y: 150), to: NSPoint(x: 930, y: 150), width: 3)
}

private func drawSunsetBeach(_ bounds: NSRect) {
    gradient(
        [
            NSColor(calibratedRed: 0.26, green: 0.18, blue: 0.42, alpha: 1),
            NSColor(calibratedRed: 0.94, green: 0.42, blue: 0.32, alpha: 1),
            NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.42, alpha: 1),
        ],
        in: NSRect(x: 0, y: 350, width: bounds.width, height: 550)
    )
    ellipse(
        NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.38, alpha: 0.95),
        NSRect(x: 820, y: 470, width: 150, height: 150)
    )
    gradient(
        [
            NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.38, alpha: 1),
            NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.42, alpha: 1),
        ],
        in: NSRect(x: 0, y: 170, width: bounds.width, height: 260)
    )
    polygon(
        [
            NSPoint(x: 0, y: 0), NSPoint(x: 0, y: 235),
            NSPoint(x: 260, y: 195), NSPoint(x: 570, y: 250),
            NSPoint(x: 910, y: 205), NSPoint(x: 1200, y: 260),
            NSPoint(x: 1200, y: 0),
        ],
        color: NSColor(calibratedRed: 0.72, green: 0.55, blue: 0.38, alpha: 1)
    )
    line(.white.withAlphaComponent(0.60), from: NSPoint(x: 100, y: 275), to: NSPoint(x: 1080, y: 310), width: 10)
    line(NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.40, alpha: 0.35), from: NSPoint(x: 895, y: 445), to: NSPoint(x: 760, y: 190), width: 38)
}

private func addFilmGrain(in bounds: NSRect) {
    var generator = SeededGenerator(seed: 0x50484F544F)
    for _ in 0..<5_000 {
        let x = CGFloat.random(in: 0..<bounds.width, using: &generator)
        let y = CGFloat.random(in: 0..<bounds.height, using: &generator)
        let white = Bool.random(using: &generator)
        let color = white ? NSColor.white : NSColor.black
        fill(color.withAlphaComponent(0.025), NSRect(x: x, y: y, width: 1.5, height: 1.5))
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
