import Foundation

/// 一张照片的本地分析结果。结果只在运行时内存中使用，不包含原图内容或路径。
struct PhotoAnalysisResult: Equatable {
    let photoID: String
    let captureDate: Date?
    let perceptualHash: PerceptualHash?
    let technicalQuality: TechnicalQuality?
    let curationCategory: PhotoCurationCategory

    init(
        photoID: String,
        captureDate: Date?,
        perceptualHash: PerceptualHash?,
        technicalQuality: TechnicalQuality?,
        curationCategory: PhotoCurationCategory = .scenery
    ) {
        self.photoID = photoID
        self.captureDate = captureDate
        self.perceptualHash = perceptualHash
        self.technicalQuality = technicalQuality
        self.curationCategory = curationCategory
    }
}

enum PhotoAnalysisMerger {
    /// 仅补充分析字段，保留用户在分析过程中做出的 Keep / Reject 决定和已有分组标记。
    static func applying(_ results: [PhotoAnalysisResult], to photos: [PhotoItem]) -> [PhotoItem] {
        var updatedPhotos = photos
        let indicesByID = Dictionary(uniqueKeysWithValues: updatedPhotos.indices.map { (updatedPhotos[$0].id, $0) })

        for result in results {
            guard let index = indicesByID[result.photoID] else { continue }
            updatedPhotos[index].captureDate = result.captureDate
            updatedPhotos[index].perceptualHash = result.perceptualHash
            updatedPhotos[index].technicalQuality = result.technicalQuality
            if !updatedPhotos[index].isCurationCategoryUserAssigned {
                updatedPhotos[index].curationCategory =
                    result.curationCategory
            }
        }
        return updatedPhotos
    }
}
