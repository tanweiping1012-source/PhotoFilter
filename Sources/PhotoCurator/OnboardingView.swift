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

/// 第一次筛选的八步。
///
/// 顺序必须和真实主链路一致：本地分析 → 按类型 AI评分 → 采纳 → 导出。
///
/// 旧版把"手动保留"排在 AI评分 之前，教出来的因果是反的：真实流程里
/// `采纳` 做的事就是 `decision = .keep`，所以"保留"是整条流程的产出，
/// 不是评分的入场券。旧版还整段跳过了本地分析——而那恰恰是真实用户
/// 第一次导入文件夹后最先看到、也最久的一屏。
enum FirstCurationGuideStep: Int, CaseIterable, Identifiable {
    case analyzePhotos
    case choosePeople
    case runPeopleAIScoring
    case viewScore
    case acceptPeopleResults
    case switchSceneryAndScore
    case acceptSceneryResults
    case exportCopies
    case completed

    static let taskCount = 8

    var id: Int { rawValue }

    var taskPosition: Int {
        min(rawValue + 1, Self.taskCount)
    }

    var systemImage: String {
        switch self {
        case .analyzePhotos: "wand.and.rays"
        case .choosePeople: "person.2.fill"
        case .runPeopleAIScoring: "wand.and.stars"
        case .viewScore: "chart.bar.xaxis"
        case .acceptPeopleResults: "checkmark.seal"
        case .switchSceneryAndScore: "mountain.2.fill"
        case .acceptSceneryResults: "checkmark.seal.fill"
        case .exportCopies: "square.and.arrow.up"
        case .completed: "checkmark.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .analyzePhotos: String(localized: "正在本地分析这 8 张照片")
        case .choosePeople: String(localized: "先查看人物照片")
        case .runPeopleAIScoring: String(localized: "为人物运行 AI评分")
        case .viewScore: String(localized: "查看 AI 为什么这样评分")
        case .acceptPeopleResults: String(localized: "采纳人物结果")
        case .switchSceneryAndScore: String(localized: "切换到风景并评分")
        case .acceptSceneryResults: String(localized: "采纳风景结果")
        case .exportCopies: String(localized: "导出保留照片的副本")
        case .completed: String(localized: "第一次筛选已完成")
        }
    }

    var detail: String {
        switch self {
        case .analyzePhotos:
            String(localized: "分开人物和风景、找出相似照片、标出技术风险。真实文件夹越大这一步越久，导入后就是从这里开始。")
        case .choosePeople:
            String(localized: "在“照片类型”中选择“人物”。人物和风景分开整理，也分开评分。")
        case .runPeopleAIScoring:
            String(localized: "在左侧“AI评分”里点击“开始人物 AI评分”，并在确认框中继续。使用内置结果，不会联网。")
        case .viewScore:
            String(localized: "选中一张已评分的照片，点底部“查看评分”；看过总分与五维评价后关掉大图即可。")
        case .acceptPeopleResults:
            String(localized: "点底部“采纳”。被采纳的照片就成为“保留”，导出时会被复制出去；最终决定始终由你做。")
        case .switchSceneryAndScore:
            String(localized: "在“照片类型”中选择“风景”，再点左侧“开始风景 AI评分”。两类分别评分、分别排序。")
        case .acceptSceneryResults:
            String(localized: "同样点底部“采纳”，把风景结果也变成保留。")
        case .exportCopies:
            String(localized: "导出 4 张后会得到“人物”和“风景”两个目录。原照片不会改变。")
        case .completed:
            String(localized: "你已经完成本地分析、AI评分、采纳确认和复制导出。点击“结束新手引导”返回。")
        }
    }

    /// 需要回到网格才能继续的步骤。
    ///
    /// AI评分 的入口在侧栏，采纳和导出的入口在底部命令条——大图盖着它们时，
    /// 教学是在让用户去点一个他看不见的按钮。第 4 步恰恰相反：它就是要留在大图里。
    var shouldClosePhotoPreview: Bool {
        switch self {
        case .runPeopleAIScoring, .acceptPeopleResults,
             .switchSceneryAndScore, .acceptSceneryResults, .exportCopies:
            true
        default:
            false
        }
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
