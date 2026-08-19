import Foundation

/// 保留这些别名以兼容既有方舟客户端；模型目录和通用限制由 AIModelCatalog 提供。
enum ArkConfiguration {
    private static let model = AIModelCatalog.model(for: .doubaoSeed20Lite)

    static let modelID = model.apiModelID
    static let responsesURL = model.endpoint
    static let maximumPhotosPerReview = AIReviewConfiguration.maximumPhotosPerReview
    static let minimumReviewInterval = AIReviewConfiguration.minimumReviewInterval
    static let providerDisplayName = model.providerAndModelDisplayName
}
