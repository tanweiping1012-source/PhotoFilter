import Foundation

enum ExportService {
    /// Copies retained photos into a new, timestamped directory. Source URLs are never written to.
    static func copy(
        photos: [PhotoItem],
        to destinationParent: URL,
        expectedCount: Int? = nil,
        now: Date = Date()
    ) throws -> URL {
        if let expectedCount, photos.count != expectedCount {
            throw ExportError.selectionCountMismatch(expected: expectedCount, actual: photos.count)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let exportURL = destinationParent.appendingPathComponent(
            "旅行照片筛选器-导出-\(formatter.string(from: now))",
            isDirectory: true
        )
        let manager = FileManager.default
        try manager.createDirectory(at: exportURL, withIntermediateDirectories: false)

        var exportedNames: [String] = []
        for photo in photos {
            let destination = uniqueDestination(for: photo.url, in: exportURL, fileManager: manager)
            try manager.copyItem(at: photo.url, to: destination)
            exportedNames.append(destination.lastPathComponent)
        }

        let manifest = ExportManifest(createdAt: now, exportedCount: exportedNames.count, filenames: exportedNames)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: exportURL.appendingPathComponent("selection.json"), options: .atomic)

        let csv = (["filename"] + exportedNames.map(csvEscaped)).joined(separator: "\n") + "\n"
        try csv.write(to: exportURL.appendingPathComponent("selection.csv"), atomically: true, encoding: .utf8)
        return exportURL
    }

    static func copyCategorized(
        photos: [PhotoItem],
        to destinationParent: URL,
        targets: PhotoSelectionTargets,
        now: Date = Date()
    ) throws -> URL {
        let photosByCategory = Dictionary(
            grouping: photos.compactMap {
                photo -> (PhotoCurationCategory, PhotoItem)? in
                guard let category = photo.curationCategory else {
                    return nil
                }
                return (category, photo)
            },
            by: \.0
        ).mapValues { $0.map(\.1) }

        for category in PhotoCurationCategory.allCases {
            let actual = photosByCategory[category, default: []].count
            let expected = targets[category]
            guard actual == expected else {
                throw ExportError.categorySelectionCountMismatch(
                    category: category,
                    expected: expected,
                    actual: actual
                )
            }
        }
        guard photosByCategory.values.reduce(0, {
            $0 + $1.count
        }) == photos.count else {
            throw ExportError.missingCategory
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let exportURL = destinationParent.appendingPathComponent(
            "旅行照片筛选器-导出-\(formatter.string(from: now))",
            isDirectory: true
        )
        let manager = FileManager.default
        try manager.createDirectory(
            at: exportURL,
            withIntermediateDirectories: false
        )

        do {
            var manifestGroups: [CategorizedExportManifest.Group] = []
            var csvRows = ["category,filename"]
            for category in PhotoCurationCategory.allCases {
                let categoryDirectory = exportURL.appendingPathComponent(
                    category.title,
                    isDirectory: true
                )
                try manager.createDirectory(
                    at: categoryDirectory,
                    withIntermediateDirectories: false
                )
                var exportedNames: [String] = []
                for photo in photosByCategory[category, default: []] {
                    let destination = uniqueDestination(
                        for: photo.url,
                        in: categoryDirectory,
                        fileManager: manager
                    )
                    try manager.copyItem(at: photo.url, to: destination)
                    exportedNames.append(destination.lastPathComponent)
                    csvRows.append(
                        [
                            csvEscaped(category.rawValue),
                            csvEscaped(
                                "\(category.title)/\(destination.lastPathComponent)"
                            ),
                        ].joined(separator: ",")
                    )
                }
                manifestGroups.append(
                    CategorizedExportManifest.Group(
                        category: category,
                        directory: category.title,
                        exportedCount: exportedNames.count,
                        filenames: exportedNames
                    )
                )
            }

            let manifest = CategorizedExportManifest(
                createdAt: now,
                exportedCount: photos.count,
                groups: manifestGroups
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(
                to: exportURL.appendingPathComponent("selection.json"),
                options: .atomic
            )
            let csv = csvRows.joined(separator: "\n") + "\n"
            try csv.write(
                to: exportURL.appendingPathComponent("selection.csv"),
                atomically: true,
                encoding: .utf8
            )
            return exportURL
        } catch {
            try? manager.removeItem(at: exportURL)
            throw error
        }
    }

    private static func uniqueDestination(for source: URL, in directory: URL, fileManager: FileManager) -> URL {
        let original = directory.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: original.path) else { return original }

        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var index = 2
        while true {
            let candidate = directory.appendingPathComponent("\(base)-\(index).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private static func csvEscaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum ExportError: LocalizedError, Equatable {
    case selectionCountMismatch(expected: Int, actual: Int)
    case categorySelectionCountMismatch(
        category: PhotoCurationCategory,
        expected: Int,
        actual: Int
    )
    case missingCategory

    var errorDescription: String? {
        switch self {
        case .selectionCountMismatch(let expected, let actual):
            String(localized: "导出需要恰好 \(expected) 张保留照片，当前为 \(actual) 张。")
        case let .categorySelectionCountMismatch(
            category,
            expected,
            actual
        ):
            String(
                localized:
                    "\(category.title)导出需要恰好 \(expected) 张，当前为 \(actual) 张。"
            )
        case .missingCategory:
            String(localized: "仍有照片未完成人物或风景分类，无法导出。")
        }
    }
}

struct CategorizedExportManifest: Codable, Equatable {
    struct Group: Codable, Equatable {
        let category: PhotoCurationCategory
        let directory: String
        let exportedCount: Int
        let filenames: [String]
    }

    let createdAt: Date
    let exportedCount: Int
    let groups: [Group]
}
