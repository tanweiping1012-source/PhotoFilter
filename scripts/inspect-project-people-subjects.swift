import Foundation

@main
struct ProjectPeopleSubjectInspector {
    private struct Row {
        let relativePath: String
        let classification: PeopleSubjectClassification
    }

    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw InspectorError.usage
        }

        let inputMode = CommandLine.arguments[1]
        let inputURL = URL(
            fileURLWithPath: CommandLine.arguments[2],
            isDirectory: inputMode == "--folder"
        )
        let outputURL = URL(
            fileURLWithPath: CommandLine.arguments[3]
        )
        let project: (name: String, folder: URL)
        let stopAccess: (() -> Void)?

        switch inputMode {
        case "--catalog":
            let resolvedProject = try resolveActiveProject(
                catalogURL: inputURL
            )
            project = (
                resolvedProject.name,
                resolvedProject.folder
            )
            stopAccess = resolvedProject.stopAccess
        case "--folder":
            project = (
                inputURL.deletingLastPathComponent()
                    .lastPathComponent
                    + " / "
                    + inputURL.lastPathComponent,
                inputURL.standardizedFileURL
            )
            stopAccess = nil
        default:
            throw InspectorError.usage
        }
        defer { stopAccess?() }

        let imageURLs = imageURLs(in: project.folder)
        guard !imageURLs.isEmpty else {
            throw InspectorError.noImages
        }

        var rows: [Row] = []
        rows.reserveCapacity(imageURLs.count)
        for (index, url) in imageURLs.enumerated() {
            let classification = PhotoCategoryClassifier
                .classifyWithEvidence(url)
            rows.append(
                Row(
                    relativePath:
                        ProjectRelativePath.make(
                            for: url,
                            relativeTo: project.folder
                        ) ?? url.lastPathComponent,
                    classification: classification
                )
            )
            if (index + 1).isMultiple(of: 25)
                || index + 1 == imageURLs.count {
                FileHandle.standardError.write(
                    Data(
                        "Analyzed \(index + 1)/\(imageURLs.count)\n"
                            .utf8
                    )
                )
            }
        }

        let report = reportText(
            projectName: project.name,
            rows: rows
        )
        try report.write(
            to: outputURL,
            atomically: true,
            encoding: .utf8
        )
        print(summaryText(rows: rows))
        print("Report: \(outputURL.path)")
    }

    private static func resolveActiveProject(
        catalogURL: URL
    ) throws -> (
        name: String,
        folder: URL,
        stopAccess: () -> Void
    ) {
        let store = PhotoProjectDiskStore(fileURL: catalogURL)
        guard let catalog = try store.load(),
              let activeProjectID = catalog.activeProjectID,
              let project = catalog.projects.first(where: {
                  $0.id == activeProjectID
              }) else {
            throw InspectorError.noActiveProject
        }

        let bookmarkAccess = SystemSecurityScopedBookmarkAccess()
        let resolved = try bookmarkAccess.resolve(
            project.bookmarkData
        )
        let didStartAccess =
            bookmarkAccess.startAccessing(resolved.url)
        let stopAccess = {
            if didStartAccess {
                bookmarkAccess.stopAccessing(resolved.url)
            }
        }
        return (
            project.displayName,
            resolved.url,
            stopAccess
        )
    }

    private static func imageURLs(in folder: URL) -> [URL] {
        let supportedExtensions: Set<String> = [
            "jpg", "jpeg", "png", "webp",
        ]
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isHiddenKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: keys
            ),
                  values.isRegularFile == true,
                  values.isHidden != true,
                  supportedExtensions.contains(
                      url.pathExtension.lowercased()
                  ) else {
                continue
            }
            urls.append(url)
        }
        return urls.sorted {
            $0.path.localizedStandardCompare($1.path)
                == .orderedAscending
        }
    }

    private static func reportText(
        projectName: String,
        rows: [Row]
    ) -> String {
        let header = [
            "# project\t\(escaped(projectName))",
            "# \(summaryText(rows: rows))",
            "relative_path\tcategory\treason\tconfidence",
        ]
        let body = rows.map { row in
            [
                escaped(row.relativePath),
                row.classification.category.rawValue,
                String(
                    describing: row.classification.reason
                ),
                String(
                    format: "%.3f",
                    row.classification.confidence
                ),
            ].joined(separator: "\t")
        }
        return (header + body).joined(separator: "\n") + "\n"
    }

    private static func summaryText(rows: [Row]) -> String {
        let peopleCount = rows.filter {
            $0.classification.category == .people
        }.count
        let sceneryCount = rows.count - peopleCount
        let failedCount = rows.filter {
            $0.classification.confidence == 0
        }.count
        let reasons = Dictionary(
            grouping: rows,
            by: {
                String(
                    describing: $0.classification.reason
                )
            }
        )
        .map { key, value in
            "\(key)=\(value.count)"
        }
        .sorted()
        .joined(separator: ", ")
        return [
            "total=\(rows.count)",
            "people=\(peopleCount)",
            "scenery=\(sceneryCount)",
            "failed=\(failedCount)",
            reasons,
        ].joined(separator: ", ")
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

private enum InspectorError: LocalizedError {
    case usage
    case noActiveProject
    case noImages

    var errorDescription: String? {
        switch self {
        case .usage:
            """
            Usage:
              inspector --catalog <projects-v1.json> <output.tsv>
              inspector --folder <photo-folder> <output.tsv>
            """
        case .noActiveProject:
            "No active persisted project is available."
        case .noImages:
            "The active project contains no supported images."
        }
    }
}
