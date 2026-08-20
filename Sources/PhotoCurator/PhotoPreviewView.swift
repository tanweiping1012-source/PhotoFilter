import AppKit
import SwiftUI

struct PhotoPreviewView: View {
    @EnvironmentObject private var library: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var previewIsFocused: Bool

    let photoIDs: [String]

    private var photo: PhotoItem? {
        library.selectedPhoto
    }

    private var currentIndex: Int? {
        guard let selectedPhotoID = library.selectedPhotoID else { return nil }
        return photoIDs.firstIndex(of: selectedPhotoID)
    }

    var body: some View {
        VStack(spacing: 0) {
            previewHeader
            if library.firstCurationGuideStep != nil {
                Divider()
                FirstCurationGuideBar(
                    compact: true,
                    completeScoreReview: {
                        library.confirmDemoScoreReview()
                        if library.firstCurationGuideStep
                            == .acceptResults {
                            dismiss()
                        }
                    },
                    finishGuide: {
                        library.finishFirstCurationGuide()
                        dismiss()
                    },
                    exitGuide: {
                        library.exitDemoMode()
                        dismiss()
                    }
                )
            }
            Divider()

            if let photo {
                HStack(spacing: 0) {
                    LargePhotoPreview(url: photo.url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    photoInspector(photo)
                        .frame(width: 320)
                }
                previewActionBar(photo)
            } else {
                ContentUnavailableView(
                    "照片不可用",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("返回照片网格后重新选择一张照片。")
                )
            }
        }
        .frame(width: 960, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($previewIsFocused)
        .onAppear {
            previewIsFocused = true
            library.recordDemoPhotoPreviewOpened()
            closePreviewIfGuideRequiresIt(
                library.firstCurationGuideStep
            )
        }
        .onChange(of: library.firstCurationGuideStep) {
            _, step in
            closePreviewIfGuideRequiresIt(step)
        }
        .onDisappear {
            library.recordDemoScoreReviewFinished()
        }
        .onKeyPress(.leftArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .accessibilityIdentifier("photo-preview")
    }

    private var previewHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(photo?.filename ?? String(localized: "照片预览"))
                    .font(.headline)
                    .lineLimit(1)
                if let currentIndex {
                    Text("\(currentIndex + 1) / \(photoIDs.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let photo {
                Label(photo.decision.title, systemImage: photo.decision.symbolName)
                    .foregroundStyle(decisionColor(photo.decision))
            }

            ControlGroup {
                Button {
                    moveSelection(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canMove(by: -1))
                .help("上一张")
                .accessibilityLabel("上一张")
                .accessibilityIdentifier("photo-preview.previous")

                Button {
                    moveSelection(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canMove(by: 1))
                .help("下一张")
                .accessibilityLabel("下一张")
                .accessibilityIdentifier("photo-preview.next")
            }
            .fixedSize()

            Button("完成") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func photoInspector(_ photo: PhotoItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !photo.aestheticRecommendations.isEmpty {
                    inspectorSection("AI评分详情") {
                        ForEach(
                            Array(
                                sortedAestheticRecommendations(for: photo)
                                    .enumerated()
                            ),
                            id: \.element.id
                        ) { index, recommendation in
                            if index > 0 {
                                Divider()
                                    .padding(.vertical, 4)
                            }
                            AestheticScoreDetailView(
                                recommendation: recommendation,
                                globalRank: recommendation.scope.kind
                                    == .finalSelection
                                    ? library.aiGlobalRank(for: photo.id)
                                    : nil,
                                isScorePreferred:
                                    recommendation.scope.kind
                                        == .finalSelection
                                    && library.aiFinalSelectionPhotoIDs
                                        .contains(photo.id)
                            )
                        }
                    }
                }

                inspectorSection("照片类型") {
                    Picker(
                        "照片类型",
                        selection: Binding(
                            get: {
                                photo.curationCategory ?? .scenery
                            },
                            set: {
                                library.setSelectedCurationCategory($0)
                            }
                        )
                    ) {
                        ForEach(PhotoCurationCategory.allCases) {
                            category in
                            Label(
                                category.title,
                                systemImage: category.systemImage
                            )
                            .tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(
                        library.isPhotoLockedByActiveAIFinalSelectionRun(photo.id)
                            || library.firstCurationGuideStep
                                == .viewScore
                    )
                    .accessibilityIdentifier(
                        "photo-preview.curation-category"
                    )
                }

                inspectorSection("照片状态") {
                    LabeledContent("决定", value: photo.decision.title)
                    if let captureDate = photo.captureDate {
                        LabeledContent("拍摄时间") {
                            Text(captureDate.formatted(date: .abbreviated, time: .standard))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if let group = photo.similarityGroup {
                    inspectorSection("相似照片") {
                        Label(
                            "第 \(group.position) / \(group.count) 张",
                            systemImage: "square.on.square"
                        )
                    }
                }

                inspectorSection("技术提示") {
                    if let quality = photo.technicalQuality,
                       !quality.risks.isEmpty {
                        ForEach(quality.risks, id: \.self) { risk in
                            Label(risk.title, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Label("没有技术风险提示", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

            }
            .padding(16)
        }
        .accessibilityIdentifier("photo-preview.inspector")
    }

    private func inspectorSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sortedAestheticRecommendations(
        for photo: PhotoItem
    ) -> [AestheticRecommendation] {
        photo.aestheticRecommendations.sorted { lhs, rhs in
            if lhs.scope.kind == .finalSelection,
               rhs.scope.kind != .finalSelection {
                return true
            }
            if lhs.scope.kind != .finalSelection,
               rhs.scope.kind == .finalSelection {
                return false
            }
            return lhs.score > rhs.score
        }
    }

    private func previewActionBar(_ photo: PhotoItem) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Button {
                    library.markSelected(as: .undecided)
                } label: {
                    Label("恢复待定", systemImage: "circle")
                }
                .disabled(
                    photo.decision == .undecided
                        || !library.canDecideSelectedPhoto
                )
                .accessibilityIdentifier("photo-preview.undecided")

                Button(role: .destructive) {
                    library.markSelected(as: .reject)
                } label: {
                    Label("淘汰", systemImage: "xmark.circle.fill")
                }
                .disabled(
                    photo.decision == .reject
                        || !library.canDecideSelectedPhoto
                )
                .accessibilityIdentifier("photo-preview.reject")

                Button {
                    library.markSelected(as: .keep)
                } label: {
                    Label("保留", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(
                    photo.decision == .keep
                        || !library.canDecideSelectedPhoto
                )
                .accessibilityIdentifier("photo-preview.keep")
                .firstCurationGuideTarget(
                    library.firstCurationGuideStep == .keepPhoto,
                    pointerSide: .trailing
                )

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)


        }
        .background(.bar)
        .accessibilityIdentifier("photo-preview.actions")
    }

    private func canMove(by offset: Int) -> Bool {
        guard let currentIndex else { return false }
        return photoIDs.indices.contains(currentIndex + offset)
    }

    private func moveSelection(by offset: Int) {
        guard let currentID = library.selectedPhotoID,
              let nextID = PhotoPreviewNavigator.photoID(
                  in: photoIDs,
                  currentID: currentID,
                  offset: offset
              ) else {
            return
        }
        library.select(nextID)
    }

    private func decisionColor(_ decision: PhotoDecision) -> Color {
        switch decision {
        case .keep: .green
        case .reject: .red
        case .undecided: .secondary
        }
    }

    private func closePreviewIfGuideRequiresIt(
        _ step: FirstCurationGuideStep?
    ) {
        guard step?.shouldClosePhotoPreview == true else {
            return
        }
        dismiss()
    }
}

struct FirstCurationGuideBar: View {
    @EnvironmentObject private var library: PhotoLibraryViewModel

    let compact: Bool
    var completeScoreReview: (() -> Void)?
    var showScoringPicks: (() -> Void)?
    var isShowingScoringPicks = false
    var finishGuide: (() -> Void)?
    var startOwnPhotos: (() -> Void)?
    var exitGuide: (() -> Void)?

    var body: some View {
        if let step = library.firstCurationGuideStep {
            HStack(spacing: 12) {
                Image(systemName: step.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        step == .completed ? Color.green : Color.accentColor
                    )
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text("第一次筛选")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if step != .completed {
                            Text(
                                "\(step.taskPosition) / \(FirstCurationGuideStep.taskCount)"
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(step.title)
                        .font(.subheadline.weight(.semibold))
                    if !compact {
                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 10)

                if step == .viewScore,
                   let completeScoreReview {
                    Button {
                        completeScoreReview()
                    } label: {
                        Label(
                            "评分已查看，继续",
                            systemImage: "arrow.right.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(
                        "guide.confirm-score-review"
                    )
                    .firstCurationGuideTarget(
                        true,
                        pointerSide: .leading
                    )
                } else if step == .acceptResults,
                          !isShowingScoringPicks,
                          let showScoringPicks {
                    Button {
                        showScoringPicks()
                    } label: {
                        Label(
                            "显示评分优先照片",
                            systemImage: "wand.and.stars"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(
                        "guide.show-scoring-picks"
                    )
                    .firstCurationGuideTarget(
                        true,
                        pointerSide: .leading
                    )
                } else if step == .runAIScoring {
                    if library.isRunningDemoAIScoring {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(
                                "离线演示 \(library.demoAIScoringCompletedPhotoCount) / \(library.aiFinalSelectionRunProgress.candidatePhotoCount) 张"
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            ProgressView(
                                value: Double(
                                    library.demoAIScoringCompletedPhotoCount
                                ),
                                total: Double(
                                    max(
                                        1,
                                        library.aiFinalSelectionRunProgress
                                            .candidatePhotoCount
                                    )
                                )
                            )
                            .frame(width: 120)
                        }
                        .firstCurationGuideTarget(
                            true,
                            pointerSide: .leading
                        )
                    } else {
                        Button {
                            library.startDemoAIScoring()
                        } label: {
                            Label("演示 AI评分", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("guide.run-ai-scoring")
                        .firstCurationGuideTarget(
                            true,
                            pointerSide: .leading
                        )
                    }
                } else if step == .completed {
                    if let startOwnPhotos {
                        Button {
                            startOwnPhotos()
                        } label: {
                            Label(
                                "开始整理我的照片",
                                systemImage: "folder.badge.plus"
                            )
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(
                            "guide.start-own-photos"
                        )
                    }

                    Button {
                        if let finishGuide {
                            finishGuide()
                        } else {
                            library.finishFirstCurationGuide()
                        }
                    } label: {
                        Label(
                            "结束新手引导",
                            systemImage: "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("guide.finish")
                    .firstCurationGuideTarget(
                        true,
                        pointerSide: .leading
                    )
                }

                Button {
                    if let exitGuide {
                        exitGuide()
                    } else {
                        library.exitDemoMode()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("退出示例筛选")
                .accessibilityLabel("退出示例筛选")
                .accessibilityIdentifier("guide.exit")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, compact ? 9 : 11)
            .background(
                step == .completed
                    ? Color.green.opacity(0.08)
                    : Color.accentColor.opacity(0.08)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("first-curation.guide")
        }
    }
}

private struct AestheticScoreDetailView: View {
    let recommendation: AestheticRecommendation
    let globalRank: Int?
    let isScorePreferred: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(scoreTitle)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(rankingLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    isScorePreferred
                        ? Color.accentColor
                        : Color(nsColor: .secondaryLabelColor)
                )
            }

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text("\(recommendation.score)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("/ 100")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("总分")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("总分")
            .accessibilityValue("\(recommendation.score) / 100")

            VStack(spacing: 8) {
                ForEach(AestheticScoreDimension.allCases) { dimension in
                    let score = dimension.score(
                        in: recommendation.dimensions
                    )
                    HStack(spacing: 8) {
                        Text(dimension.title)
                            .font(.caption)
                            .frame(width: 72, alignment: .leading)
                        ProgressView(
                            value: Double(score),
                            total: 100
                        )
                        .progressViewStyle(.linear)
                        .accessibilityHidden(true)
                        Text("\(score)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dimension.title)
                    .accessibilityValue("\(score) / 100")
                    .accessibilityIdentifier(
                        "photo-preview.score.\(dimension.rawValue)"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("具体评价")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(
                    Array(recommendation.reasons.enumerated()),
                    id: \.offset
                ) { _, reason in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.secondary)
                        Text(reason)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("AI总结")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(recommendation.summary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "photo-preview.score-detail.\(recommendation.id)"
        )
    }

    private var rankingLabel: String {
        guard let globalRank else {
            return String(localized: "独立评分")
        }
        let category = recommendation.scope.category?.title
            ?? String(localized: "分类")
        return isScorePreferred
            ? String(localized: "\(category)第 \(globalRank) 名 · 评分优先")
            : String(localized: "\(category)第 \(globalRank) 名")
    }

    private var scoreTitle: String {
        guard let category = recommendation.scope.category else {
            return recommendation.scope.kind.title
        }
        return String(localized: "\(category.title) AI评分")
    }
}

enum PhotoPreviewNavigator {
    static func photoID(
        in photoIDs: [String],
        currentID: String,
        offset: Int
    ) -> String? {
        guard let currentIndex = photoIDs.firstIndex(of: currentID) else {
            return photoIDs.first
        }
        let nextIndex = currentIndex + offset
        guard photoIDs.indices.contains(nextIndex) else { return nil }
        return photoIDs[nextIndex]
    }
}

private struct LargePhotoPreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .accessibilityLabel("正在载入大图预览")
            }
        }
        .task(id: url) {
            image = nil
            image = await ThumbnailCache.shared.image(
                for: url,
                maximumPixelSize: 1_600
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("照片大图预览")
    }
}
