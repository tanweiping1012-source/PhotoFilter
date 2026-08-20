import SwiftUI

enum OnboardingPreferenceStore {
    static let currentVersion = 3
    static let completedVersionKey = "completed-onboarding-version-v3"

    static func shouldPresent(
        isDemoModeActive: Bool,
        defaults: UserDefaults = .standard
    ) -> Bool {
        !isDemoModeActive
            && defaults.integer(forKey: completedVersionKey) < currentVersion
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: completedVersionKey)
    }
}

enum FirstCurationGuideStep: Int, CaseIterable, Identifiable {
    case choosePeople
    case inspectPhoto
    case keepPhoto
    case runAIScoring
    case switchToScenery
    case viewScore
    case acceptResults
    case exportCopies
    case completed

    static let taskCount = 8

    var id: Int { rawValue }

    var taskPosition: Int {
        min(rawValue + 1, Self.taskCount)
    }

    var systemImage: String {
        switch self {
        case .choosePeople: "person.2.fill"
        case .inspectPhoto: "photo.on.rectangle.angled"
        case .keepPhoto: "checkmark.circle"
        case .runAIScoring: "wand.and.stars"
        case .switchToScenery: "mountain.2.fill"
        case .viewScore: "chart.bar.xaxis"
        case .acceptResults: "checkmark.seal"
        case .exportCopies: "square.and.arrow.up"
        case .completed: "checkmark.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .choosePeople: String(localized: "先查看人物照片")
        case .inspectPhoto: String(localized: "打开任意一张照片")
        case .keepPhoto: String(localized: "先保留这张照片")
        case .runAIScoring: String(localized: "运行离线 AI评分")
        case .switchToScenery: String(localized: "切换到风景照片")
        case .viewScore: String(localized: "查看 AI 为什么这样评分")
        case .acceptResults: String(localized: "查看并采纳评分结果")
        case .exportCopies: String(localized: "导出保留照片的副本")
        case .completed: String(localized: "第一次筛选已完成")
        }
    }

    var detail: String {
        switch self {
        case .choosePeople:
            String(localized: "在“照片类型”中选择“人物”。人物和风景会分开整理。")
        case .inspectPhoto:
            String(localized: "双击任意人物照片，或选中后点击“预览”。")
        case .keepPhoto:
            String(localized: "在大图中点击“保留”。最终决定始终由你完成。")
        case .runAIScoring:
            String(localized: "运行内置固定评分；人物和风景会使用不同重点分别排序，不会联网。")
        case .switchToScenery:
            String(localized: "在“照片类型”中选择“风景”，查看独立的风景结果。")
        case .viewScore:
            String(localized: "检查总分、五维评分、具体评价和总结，然后点击“评分已查看，继续”。")
        case .acceptResults:
            String(localized: "点击“显示 AI 评分结果”，按分数逐张看过后再采纳人物和风景结果。")
        case .exportCopies:
            String(localized: "导出 4 张后会得到“人物”和“风景”两个目录。原照片不会改变。")
        case .completed:
            String(localized: "你已经完成检查、AI评分、人工确认和复制导出。点击“结束新手引导”返回。")
        }
    }

    var shouldClosePhotoPreview: Bool {
        self == .switchToScenery
    }
}

struct OnboardingView: View {
    let startSamplePractice: () -> Void
    let choosePhotoFolder: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("第一次筛选")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("稍后再说") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.dismiss")
            }

            Spacer(minLength: 24)

            VStack(spacing: 14) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 72, height: 64)

                Text("从一段旅程中，选出真正值得保留的照片")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("适合旅行结束后，把人物和风景分开整理与评分，再决定各自保留哪些照片。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 540)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 24)

            CurationFlowView()

            Spacer(minLength: 26)

            VStack(spacing: 10) {
                Button {
                    startSamplePractice()
                } label: {
                    Label("体验一次完整筛选", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.start-sample")

                Button {
                    choosePhotoFolder()
                } label: {
                    Label("选择我的照片", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.choose-folder")

                Text("完整体验使用 4 张人物、4 张风景和离线固定评分，不读取你的照片、Keychain 或网络。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(30)
        .frame(width: 680, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("onboarding")
    }
}

private struct CurationFlowView: View {
    private let steps: [(String, String)] = [
        ("folder", String(localized: "选择照片")),
        ("person.2", String(localized: "分开类型")),
        ("eye", String(localized: "检查决定")),
        ("wand.and.stars", String(localized: "可选 AI评分")),
        ("checkmark.seal", String(localized: "确认保留")),
        ("square.and.arrow.up", String(localized: "导出副本")),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(spacing: 7) {
                    Image(systemName: step.0)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(index == 2 ? Color.accentColor : .primary)
                        .frame(width: 28, height: 24)
                    Text(step.1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                if index < steps.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("筛选流程")
        .accessibilityValue("选择照片、检查决定、可选 AI评分、确认保留、导出副本")
    }
}
