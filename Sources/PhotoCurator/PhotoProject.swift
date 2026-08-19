import Foundation

enum PhotoProjectAccessState: Equatable {
    case available
    case needsAuthorization
}

/// 筛选项目只在内存中持有已解析目录；跨启动仅保存安全书签与可读显示名。
struct PhotoProject: Identifiable, Equatable {
    let id: UUID
    var folderURL: URL?
    let createdAt: Date
    var storedDisplayName: String
    var photoCount: Int
    var isAnalysisComplete: Bool
    var accessState: PhotoProjectAccessState

    init(
        id: UUID = UUID(),
        folderURL: URL,
        createdAt: Date = Date(),
        photoCount: Int = 0,
        isAnalysisComplete: Bool = false
    ) {
        self.id = id
        self.folderURL = folderURL.standardizedFileURL
        self.createdAt = createdAt
        self.storedDisplayName = Self.makeDisplayName(for: folderURL)
        self.photoCount = photoCount
        self.isAnalysisComplete = isAnalysisComplete
        self.accessState = .available
    }

    init(
        id: UUID,
        folderURL: URL?,
        displayName: String,
        createdAt: Date,
        photoCount: Int,
        accessState: PhotoProjectAccessState
    ) {
        self.id = id
        self.folderURL = folderURL?.standardizedFileURL
        self.createdAt = createdAt
        self.storedDisplayName = displayName
        self.photoCount = photoCount
        self.isAnalysisComplete = false
        self.accessState = accessState
    }

    var displayName: String {
        storedDisplayName
    }

    mutating func reconnect(to folderURL: URL) {
        self.folderURL = folderURL.standardizedFileURL
        storedDisplayName = Self.makeDisplayName(for: folderURL)
        accessState = .available
        isAnalysisComplete = false
    }

    private static func makeDisplayName(for folderURL: URL) -> String {
        let folderName = folderURL.lastPathComponent
        let parentName = folderURL.deletingLastPathComponent().lastPathComponent
        guard !parentName.isEmpty, parentName != "/" else { return folderName }
        return "\(parentName) / \(folderName)"
    }
}

enum PhotoProjectCatalog {
    static func project(for folderURL: URL, in projects: [PhotoProject]) -> PhotoProject? {
        let standardizedURL = folderURL.standardizedFileURL
        return projects.first { $0.folderURL == standardizedURL }
    }

    static func removing(_ projectID: UUID, from projects: [PhotoProject]) -> [PhotoProject] {
        projects.filter { $0.id != projectID }
    }
}
