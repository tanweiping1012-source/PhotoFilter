import Foundation

enum AIModelConnectionVerificationError: LocalizedError {
    case testImageUnavailable
    case invalidResult

    var errorDescription: String? {
        switch self {
        case .testImageUnavailable:
            String(localized: "内置连接测试图片不可用，未发送请求。")
        case .invalidResult:
            String(localized: "模型返回了响应，但未通过照片评分契约校验。")
        }
    }
}

struct AIModelConnectionVerifier {
    static let testImageFilename = "demo-01-coastal-road.jpg"

    func verify(
        model: AIModelDescriptor,
        apiKey: String,
        previewSize: AIReviewPreviewSize = .small,
        session: URLSession = AIReviewURLSession.shared,
        testImageURL: URL? = nil
    ) async throws {
        let imageURL = testImageURL ?? Self.testImageURL()
        guard let imageURL else {
            throw AIModelConnectionVerificationError.testImageUnavailable
        }

        let scope = AestheticReviewScope(
            kind: .finalSelection,
            groupID: "connection-verification",
            category: .scenery
        )
        let request = AestheticReviewRequestBuilder.make(
            scope: scope,
            localPhotoIDs: ["connection-test-photo"],
            requestID: "connection-test"
        )
        let jpegData = try AIReviewPreviewEncoder.jpegData(
            for: imageURL,
            maximumPixelSize: previewSize.maximumPixelSize
        )
        guard let opaquePhotoID = request.photos.first?.photoID else {
            throw AIModelConnectionVerificationError.invalidResult
        }
        let result = try await AestheticReviewClient(model: model).review(
            request: request,
            previews: [
                AestheticReviewPreview(
                    opaquePhotoID: opaquePhotoID,
                    jpegData: jpegData
                ),
            ],
            previewSize: previewSize,
            apiKey: apiKey,
            session: session
        )
        try AestheticReviewValidator.validate(
            result.response,
            for: request
        )
        guard result.response.reviews.count == 1 else {
            throw AIModelConnectionVerificationError.invalidResult
        }
    }

    private static func testImageURL(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates = [
            bundle.resourceURL?
                .appendingPathComponent("DemoPhotos", isDirectory: true)
                .appendingPathComponent(testImageFilename),
            URL(
                fileURLWithPath: fileManager.currentDirectoryPath,
                isDirectory: true
            )
            .appendingPathComponent("Resources/DemoPhotos", isDirectory: true)
            .appendingPathComponent(testImageFilename),
        ].compactMap { $0 }

        return candidates.first {
            fileManager.fileExists(atPath: $0.path)
        }
    }
}
