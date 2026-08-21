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
        // 完成态不再重复流程的名字。任务条上"第一次筛选"这句话已经删掉了，
        // 标题里再写一遍就是同一句话说两次，而用户此刻要看的是"走完了几步"。
        case .completed: String(localized: "已完成全部 \(Self.taskCount) 步")
        }
    }

    /// 每一步都必须同时回答"做什么"和"这一步意味着什么"。
    ///
    /// 只说"点这里"教出来的是肌肉记忆：用户学会了按顺序点，却不知道评分和保留
    /// 是什么关系、为什么人物和风景要分开。这些概念此前散在顶部状态行的旁白里，
    /// 而旁白和任务条同时出现，同一步说两遍，重要的那半反而被当成重复噪音。
    var detail: String {
        switch self {
        case .analyzePhotos:
            String(localized: "全部在本机完成，不联网。这一步会找出相似照片、区分人物与风景，并标出曝光和清晰度风险——真实文件夹越大越久。")
        case .choosePeople:
            String(localized: "在“照片类型”中选择“人物”。人像和风景的好照片标准不同，所以两类分开评分、分开排序，保留目标也各自计算。")
        case .runPeopleAIScoring:
            String(localized: "在左侧“AI评分”里点击“开始人物 AI评分”，并在确认框中继续。真实流程到这一步才会联网、才会产生费用；示例用内置结果，不联网也不消耗额度。")
        case .viewScore:
            String(localized: "选中一张已评分的照片，点底部“查看评分”。分数只是解释和排序的依据，它本身不改变任何照片的去留。看完关掉大图即可。")
        case .acceptPeopleResults:
            String(localized: "点底部“采纳”。这一步才把 AI 的建议变成“保留”——在此之前评分没有动过任何一张照片。采纳同样可以撤销。")
        case .switchSceneryAndScore:
            String(localized: "在“照片类型”中选择“风景”，再点左侧“开始风景 AI评分”。人物和风景从不互相比较，各自排各自的名次。")
        case .acceptSceneryResults:
            String(localized: "同样点底部“采纳”，把风景结果也变成保留。两类的保留目标各自独立，互不占用。")
        case .exportCopies:
            String(localized: "导出 4 张后会得到“人物”和“风景”两个目录。导出是复制：原照片不会被移动、删除或修改。")
        case .completed:
            String(localized: "你已经完成本地分析、AI评分、采纳确认和复制导出。换成自己的照片文件夹，流程完全一样。点击“结束新手引导”返回。")
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
                    .font(Typography.paneTitle)
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
                    .font(Typography.heroIcon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 72, height: 64)

                Text("从一段旅程中，选出真正值得保留的照片")
                    .font(Typography.heroTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("适合旅行结束后，把人物和风景分开整理与评分，再决定各自保留哪些照片。")
                    .font(Typography.heroBody)
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
                    .font(Typography.detail)
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
                        .font(Typography.heroStepIcon)
                        .foregroundStyle(index == 2 ? Color.accentColor : .primary)
                        .frame(width: 28, height: 24)
                    Text(step.1)
                        .font(Typography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                if index < steps.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(Typography.footnote)
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
