import AppKit
import Foundation

@main
struct PeopleClassificationContactSheet {
    private struct Row {
        let relativePath: String
        let category: String
        let reason: String
        let confidence: String
    }

    static func main() throws {
        guard CommandLine.arguments.count == 6 else {
            throw RendererError.usage
        }

        let folderURL = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let reportURL = URL(
            fileURLWithPath: CommandLine.arguments[2]
        )
        let field = CommandLine.arguments[3]
        let value = CommandLine.arguments[4]
        let outputURL = URL(
            fileURLWithPath: CommandLine.arguments[5]
        )
        let rows = try reportRows(reportURL).filter { row in
            switch field {
            case "category":
                row.category == value
            case "reason":
                row.reason == value
            default:
                false
            }
        }
        guard !rows.isEmpty else {
            throw RendererError.noMatchingRows
        }

        let columns = 5
        let cellSize = NSSize(width: 260, height: 220)
        let rowCount = Int(
            ceil(Double(rows.count) / Double(columns))
        )
        let canvasSize = NSSize(
            width: cellSize.width * Double(columns),
            height: cellSize.height * Double(rowCount)
        )
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width),
            pixelsHigh: Int(canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
              let context = NSGraphicsContext(
                  bitmapImageRep: representation
              ) else {
            throw RendererError.cannotEncode
        }
        representation.size = canvasSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        for (index, row) in rows.enumerated() {
            let column = index % columns
            let visualRow = index / columns
            let cellOrigin = NSPoint(
                x: Double(column) * cellSize.width,
                y: canvasSize.height
                    - Double(visualRow + 1) * cellSize.height
            )
            draw(
                row,
                folderURL: folderURL,
                in: NSRect(origin: cellOrigin, size: cellSize)
            )
        }

        context.flushGraphics()
        guard let png = representation.representation(
                  using: .png,
                  properties: [:]
              ) else {
            throw RendererError.cannotEncode
        }
        try png.write(to: outputURL, options: .atomic)
        print(outputURL.path)
    }

    private static func reportRows(
        _ reportURL: URL
    ) throws -> [Row] {
        let content = try String(
            contentsOf: reportURL,
            encoding: .utf8
        )
        return content.split(separator: "\n")
            .dropFirst(3)
            .compactMap { line in
                let columns = line.split(
                    separator: "\t",
                    omittingEmptySubsequences: false
                )
                guard columns.count == 4 else { return nil }
                return Row(
                    relativePath: String(columns[0]),
                    category: String(columns[1]),
                    reason: String(columns[2]),
                    confidence: String(columns[3])
                )
            }
    }

    private static func draw(
        _ row: Row,
        folderURL: URL,
        in cell: NSRect
    ) {
        NSColor(
            calibratedWhite: 0.96,
            alpha: 1
        ).setFill()
        cell.insetBy(dx: 5, dy: 5).fill()

        let imageURL = folderURL.appendingPathComponent(
            row.relativePath
        )
        let imageRect = NSRect(
            x: cell.minX + 10,
            y: cell.minY + 36,
            width: cell.width - 20,
            height: cell.height - 46
        )
        if let image = NSImage(contentsOf: imageURL) {
            image.draw(
                in: imageRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [
                    .interpolation:
                        NSImageInterpolation.high.rawValue,
                ]
            )
        } else {
            NSColor.systemRed.setFill()
            imageRect.fill()
        }

        let title = URL(
            fileURLWithPath: row.relativePath
        ).lastPathComponent
        let detail = "\(row.reason) · \(row.confidence)"
        drawText(
            title,
            in: NSRect(
                x: cell.minX + 10,
                y: cell.minY + 19,
                width: cell.width - 20,
                height: 15
            ),
            font: .systemFont(ofSize: 11, weight: .semibold)
        )
        drawText(
            detail,
            in: NSRect(
                x: cell.minX + 10,
                y: cell.minY + 5,
                width: cell.width - 20,
                height: 14
            ),
            font: .monospacedSystemFont(
                ofSize: 9,
                weight: .regular
            )
        )
    }

    private static func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont
    ) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
            ]
        )
    }
}

private enum RendererError: LocalizedError {
    case usage
    case noMatchingRows
    case cannotEncode

    var errorDescription: String? {
        switch self {
        case .usage:
            """
            Usage: renderer <folder> <report.tsv> \
            <category|reason> <value> <output.png>
            """
        case .noMatchingRows:
            "The report has no matching rows."
        case .cannotEncode:
            "The contact sheet could not be encoded."
        }
    }
}
