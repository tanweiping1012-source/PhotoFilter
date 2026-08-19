import Foundation

struct PersistedPhotoProject: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    var bookmarkData: Data
    var displayName: String
    let createdAt: Date
    var lastOpenedAt: Date
    var lastKnownPhotoCount: Int
    var targetSelectionCount: Int
    var selectionTargets: PhotoSelectionTargets?
    var decisionsByRelativePath: [String: PhotoDecision]
    var categoryOverridesByRelativePath: [String: PhotoCurationCategory]?
    var selectedRelativePath: String?

    init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID,
        bookmarkData: Data,
        displayName: String,
        createdAt: Date,
        lastOpenedAt: Date = Date(),
        lastKnownPhotoCount: Int = 0,
        targetSelectionCount: Int = 12,
        selectionTargets: PhotoSelectionTargets? = nil,
        decisionsByRelativePath: [String: PhotoDecision] = [:],
        categoryOverridesByRelativePath: [String: PhotoCurationCategory]? = nil,
        selectedRelativePath: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.bookmarkData = bookmarkData
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.lastKnownPhotoCount = lastKnownPhotoCount
        self.targetSelectionCount = targetSelectionCount
        self.selectionTargets = selectionTargets
        self.decisionsByRelativePath = decisionsByRelativePath
        self.categoryOverridesByRelativePath =
            categoryOverridesByRelativePath
        self.selectedRelativePath = selectedRelativePath
    }
}

struct PersistedPhotoProjectCatalog: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var activeProjectID: UUID?
    var projects: [PersistedPhotoProject]

    init(
        schemaVersion: Int = currentSchemaVersion,
        activeProjectID: UUID?,
        projects: [PersistedPhotoProject]
    ) {
        self.schemaVersion = schemaVersion
        self.activeProjectID = activeProjectID
        self.projects = projects
    }
}

protocol PhotoProjectPersisting {
    func load() throws -> PersistedPhotoProjectCatalog?
    func save(_ catalog: PersistedPhotoProjectCatalog) throws
}

struct PhotoProjectDiskStore: PhotoProjectPersisting {
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() throws -> PersistedPhotoProjectCatalog? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(PersistedPhotoProjectCatalog.self, from: data)
        guard catalog.schemaVersion == PersistedPhotoProjectCatalog.currentSchemaVersion,
              catalog.projects.allSatisfy({ $0.schemaVersion == PersistedPhotoProject.currentSchemaVersion }) else {
            throw ProjectPersistenceError.unsupportedSchema
        }
        return catalog
    }

    func save(_ catalog: PersistedPhotoProjectCatalog) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(catalog).write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let applicationNamespace = Bundle.main.bundleIdentifier ?? "com.photocurator.local"
        return applicationSupport
            .appendingPathComponent(applicationNamespace, isDirectory: true)
            .appendingPathComponent("projects-v1.json", isDirectory: false)
    }
}

enum ProjectPersistenceError: LocalizedError {
    case unsupportedSchema
    case inaccessibleBookmark

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            String(localized: "项目状态版本不受支持，需要重新创建项目。")
        case .inaccessibleBookmark:
            String(localized: "项目文件夹权限已失效，需要重新授权。")
        }
    }
}

struct ResolvedProjectBookmark {
    let url: URL
    let isStale: Bool
}

protocol SecurityScopedBookmarkAccessing {
    func makeReadOnlyBookmark(for folderURL: URL) throws -> Data
    func resolve(_ bookmarkData: Data) throws -> ResolvedProjectBookmark
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

struct SystemSecurityScopedBookmarkAccess: SecurityScopedBookmarkAccessing {
    func makeReadOnlyBookmark(for folderURL: URL) throws -> Data {
        try folderURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolve(_ bookmarkData: Data) throws -> ResolvedProjectBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedProjectBookmark(url: url.standardizedFileURL, isStale: isStale)
    }

    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

enum ProjectRelativePath {
    static func make(for fileURL: URL, relativeTo folderURL: URL) -> String? {
        let rootComponents = folderURL.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
