import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: PhotoLibraryViewModel
    @State private var showAISettings = false
    @State private var showOnboarding = false
    @State private var showPrivacyInformation = false
    @State private var showSupportInformation = false
    @State private var showPhotoPreview = false
    @State private var previewPhotoIDs: [String] = []
    @State private var gridFilter: PhotoGridFilter = .all
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var focusedPhotoID: String?

    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 12)]

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            projectSidebar
                .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 340)
        } detail: {
            photoGrid
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 920, minHeight: 640)
        .accessibilityIdentifier("photo-curator.main")
        .alert("确认复制导出", isPresented: $library.showExportConfirmation) {
            Button("取消", role: .cancel) {}
            Button("复制人物与风景精选") {
                library.exportKeepers()
            }
        } message: {
            Text(
                exportConfirmationMessage
            )
        }
        .alert("开始 AI评分？", isPresented: $library.showAIFinalSelectionRunConfirmation) {
            Button("取消", role: .cancel) {}
            Button(aiFinalSelectionConfirmationButtonTitle) {
                library.submitConfirmedAIFinalSelectionRun()
            }
        } message: {
            Text(aiFinalSelectionConfirmationMessage)
        }
        .alert("删除筛选项目？", isPresented: $library.showProjectDeletionConfirmation) {
            Button("取消", role: .cancel) { library.cancelProjectDeletion() }
            Button("删除项目", role: .destructive) { library.confirmDeleteProject() }
        } message: {
            Text("只会删除 App 内的项目状态并释放缩略图缓存，不会删除、移动或修改文件夹中的任何照片。")
        }
        .sheet(isPresented: $showAISettings) {
            AISettingsView(
                selectedModelID: $library.selectedAIModelID,
                selectedPreviewSize: $library.selectedAIPreviewSize,
                isConfigurationLocked: library.isAIConfigurationLocked,
                didChangeConfiguration: library.refreshAIConfiguration
            )
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                startSamplePractice: startSamplePractice,
                choosePhotoFolder: choosePhotoFolderFromOnboarding,
                dismiss: dismissOnboarding
            )
        }
        .sheet(isPresented: $showPrivacyInformation) {
            PrivacyInformationView()
        }
        .sheet(isPresented: $showSupportInformation) {
            SupportInformationView(isDemoModeActive: library.isDemoModeActive)
        }
        .sheet(isPresented: $showPhotoPreview) {
            // 看完评分后关掉大图，就是"我看过了"。以前这里需要一个只在教学期间
            // 存在的"评分已查看，继续"按钮，用户学到的是一个用完就消失的控件。
            library.confirmDemoScoreReview()
        } content: {
            PhotoPreviewView(photoIDs: previewPhotoIDs)
                .environmentObject(library)
        }
        .onChange(of: library.completionNotice) { _, notice in
            guard case .aiScoring = notice?.kind else { return }
            // 评分完成后直接落在这一类的“已AI评分”上：这里能看到本轮全部候选的分数和排序。
            // 类型由 ViewModel 一并切好，用户不需要自己回想该切回哪个类型、该选哪个筛选。
            gridFilter = .aiScored
        }
        .onChange(of: library.activeProjectID) { _, _ in
            showPhotoPreview = false
            // 筛选器是窗口级状态，会跨项目残留。新项目（尤其是从未评分开始的教学项目）
            // 在“待AI评分”这类筛选下可能是 0 张，用户会既看不到照片也无法推进教学。
            gridFilter = .all
        }
        .onAppear {
            guard OnboardingPreferenceStore.shouldPresent(
                isDemoModeActive: library.isDemoModeActive
            ) else {
                return
            }
            showOnboarding = true
        }
    }

    private var projectSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("照片筛选项目")
                        .font(Typography.paneTitle)
                    Text("每个日期文件夹是一项独立任务")
                        .font(Typography.paneSubtitle)
                        .foregroundStyle(.secondary)
                }

                Button {
                    library.chooseFolder()
                } label: {
                    Label("新建筛选项目", systemImage: "folder.badge.plus")
                        .labelStyle(SidebarEntryLabelStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .disabled(library.isProjectNavigationLocked)
                .accessibilityIdentifier("sidebar.new-project")

                if !library.isDemoModeActive {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("新手引导", systemImage: "graduationcap")
                            .labelStyle(SidebarEntryLabelStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(library.isProjectNavigationLocked)
                    .accessibilityIdentifier("sidebar.onboarding")

                    Button {
                        showAISettings = true
                    } label: {
                        Label("AI评分设置", systemImage: "gearshape")
                            .labelStyle(SidebarEntryLabelStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sidebar.ai-settings")
                }

                if let reason = library.projectNavigationLockReason {
                    Text(reason)
                        .font(Typography.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sidebar.navigation-lock-reason")
                }
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if library.projects.isEmpty {
                        ContentUnavailableView(
                            "还没有项目",
                            systemImage: "folder",
                            description: Text("选择一个日期文件夹开始本地筛选。")
                        )
                        .padding(.vertical, 32)
                    } else {
                        Text("项目")
                            .font(Typography.sectionTitle)

                        ForEach(library.projects) { project in
                            projectRow(project)
                        }
                    }

                    if library.activeProject != nil {
                        Divider().padding(.vertical, 8)
                        activeProjectControls
                    }
                }
                .padding()
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    showSupportInformation = true
                } label: {
                    Label("帮助与支持", systemImage: "questionmark.circle")
                        .labelStyle(SidebarEntryLabelStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.support")
                .accessibilityHint("查看常见问题和复制非敏感诊断信息")

                Button {
                    showPrivacyInformation = true
                } label: {
                    Label("隐私与数据", systemImage: "hand.raised")
                        .labelStyle(SidebarEntryLabelStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.privacy")
                .accessibilityHint("查看本地处理、AI 发送边界与数据删除方式")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 270)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func projectRow(_ project: PhotoProject) -> some View {
        let isActive = project.id == library.activeProjectID
        return HStack(spacing: 8) {
            Button {
                library.activateProject(project.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: projectIcon(project, isActive: isActive))
                        .foregroundStyle(project.accessState == .needsAuthorization ? Color.orange : (isActive ? Color.accentColor : .secondary))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.displayName)
                            .font(
                                isActive
                                    ? Typography.rowLabelActive
                                    : Typography.rowLabel
                            )
                            .lineLimit(2)
                        Text(projectStatusText(project))
                            .font(Typography.detailNumeric)
                            .foregroundStyle(project.accessState == .needsAuthorization ? .orange : .secondary)
                        if isActive, library.analysisProgressLabel != nil {
                            ProgressView(value: library.analysisProgress)
                                .accessibilityLabel("本地分析进度")
                                .accessibilityValue(projectStatusText(project))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(library.isProjectNavigationLocked && !isActive)
            .accessibilityIdentifier("project.row.\(project.id.uuidString)")
            .accessibilityLabel(project.displayName)
            .accessibilityValue(projectAccessibilityValue(project, isActive: isActive))
            .accessibilityHint(projectAccessibilityHint(project, isActive: isActive))
            .firstCurationGuideTarget(
                isActive && library.firstCurationGuideStep == .analyzePhotos,
                pointerSide: .noPointer,
                cornerRadius: 10
            )

            if library.isDemoProject(project) {
                Button {
                    library.exitDemoMode()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("project.close-demo")
                .accessibilityLabel("退出示例筛选")
            } else {
                Button(role: .destructive) {
                    library.requestDeleteProject(project.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("project.delete.\(project.id.uuidString)")
                .accessibilityLabel("删除项目 \(project.displayName)")
            }
        }
        .padding(10)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.accentColor.opacity(0.45) : Color.clear)
        }
    }

    private func projectStatusText(_ project: PhotoProject) -> String {
        if library.isDemoProject(project) {
            return String(localized: "8 张 · 示例筛选")
        }
        if project.accessState == .needsAuthorization {
            return String(localized: "需要重新授权 · 点按项目")
        }
        if project.id == library.activeProjectID,
           library.analysisProgressLabel != nil,
           library.analysisTotal > 0 {
            return String(
                localized: "分析中 \(library.analysisCompleted) / \(library.analysisTotal) 张"
            )
        }
        return project.photoCount == 0
            ? String(localized: "等待扫描")
            : String(
                localized: "\(project.photoCount) 张 · \(project.isAnalysisComplete ? String(localized: "分析完成") : String(localized: "分析中"))"
            )
    }

    private func projectIcon(_ project: PhotoProject, isActive: Bool) -> String {
        if library.isDemoProject(project) {
            return isActive ? "play.rectangle.fill" : "play.rectangle"
        }
        if project.accessState == .needsAuthorization {
            return "folder.badge.questionmark"
        }
        return isActive ? "folder.fill" : "folder"
    }

    private func projectAccessibilityValue(_ project: PhotoProject, isActive: Bool) -> String {
        let status = projectStatusText(project)
        guard isActive else { return status }
        return [String(localized: "当前项目"), status].formatted(.list(type: .and))
    }

    private func projectAccessibilityHint(_ project: PhotoProject, isActive: Bool) -> String {
        if project.accessState == .needsAuthorization {
            return String(localized: "重新授权照片文件夹")
        }
        return isActive ? "" : String(localized: "切换到此项目")
    }

    private func completeOnboarding() {
        OnboardingPreferenceStore.markCompleted()
    }

    private func dismissOnboarding() {
        completeOnboarding()
        showOnboarding = false
    }

    private func startSamplePractice() {
        completeOnboarding()
        showOnboarding = false
        Task { @MainActor in
            await Task.yield()
            library.startDemoMode()
        }
    }

    private func choosePhotoFolderFromOnboarding() {
        completeOnboarding()
        showOnboarding = false
        Task { @MainActor in
            await Task.yield()
            library.chooseFolder()
        }
    }

    private func startOwnPhotosAfterGuide() {
        library.exitDemoMode()
        Task { @MainActor in
            await Task.yield()
            library.chooseFolder()
        }
    }

    private var activeProjectControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("保留目标")
                    .font(Typography.sectionTitle)
                ForEach(PhotoCurationCategory.allCases) { category in
                    selectionTargetRow(category)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("selection.targets")

            if library.keeperDiversityConflictCount > 0 {
                Label("已有 \(library.keeperDiversityConflictCount) 组重复照片被同时保留，请每组只留一张。", systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.detail)
                    .foregroundStyle(.orange)
            }

            compactAIControls
        }
    }

    private func selectionTargetRow(
        _ category: PhotoCurationCategory
    ) -> some View {
        let target = library.targetSelectionCount(for: category)
        let counts = library.counts(in: category)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Label(category.title, systemImage: category.systemImage)
                    .font(Typography.rowLabel)
                Spacer()
                Stepper(
                    "\(target)",
                    value: Binding(
                        get: {
                            library.targetSelectionCount(for: category)
                        },
                        set: {
                            library.updateTargetSelectionCount(
                                $0,
                                for: category
                            )
                        }
                    ),
                    in: 0...999
                )
                .labelsHidden()
                .disabled(
                    library.isLockedByActiveAIFinalSelectionRun(category)
                        || library.isDemoModeActive
                )
                Text("\(target) 张")
                    .font(Typography.rowValue)
                    .frame(width: 44, alignment: .trailing)
            }
            ProgressView(
                value: Double(min(counts.keep, target)),
                total: Double(max(1, target))
            )
            .accessibilityLabel("\(category.title)保留进度")
            .accessibilityValue("已保留 \(counts.keep) 张，共需 \(target) 张")
            Text(
                "保留 \(counts.keep) · 淘汰 \(counts.reject) · 待定 \(counts.undecided)"
            )
            .font(Typography.detailNumeric)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier(
            "selection.target.\(category.rawValue)"
        )
    }

    private var compactAIControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI评分")
                    .font(Typography.sectionTitle)
            }

            // 示例里不显示这一行：它统计的是"真实评分的候选池"（会排除已保留项和
            // 相似重复项），而离线教学按整个类型给分。两个数并排出现（待评分 2 张 /
            // 开始人物 AI评分（4 张））只会让人以为哪个是错的。示例里每个按钮
            // 自己带着张数，已经够用。
            if !library.isDemoModeActive,
               !library.localAestheticCandidatePhotoIDs.isEmpty {
                Text("待评分 \(library.localAestheticCandidatePhotoIDs.count) 张")
                    .font(Typography.detail)
                    .foregroundStyle(.secondary)
            }

            if library.isDemoModeActive {
                Label("离线教学", systemImage: "graduationcap")
                    .foregroundStyle(Color.accentColor)
                Text("不联网，不读取 Keychain，不消耗 API 额度。")
                    .font(Typography.detail)
                    .foregroundStyle(.secondary)
                if library.isRunningDemoAIScoring {
                    ProgressView(
                        value: library.displayedAIFinalSelectionRunProgress
                            .fractionCompleted
                    )
                    Text(
                        "正在评估 · \(library.demoAIScoringCompletedPhotoCount)/\(library.displayedAIFinalSelectionRunProgress.candidatePhotoCount) 张"
                    )
                    .font(Typography.detailNumeric)
                } else {
                    // 教学要驱动的就是这个真实入口，所以它在示例里也必须出现在同一位置。
                    // 这一支以前只画"离线教学"说明、不画按钮，教学走到第 4 步就没有
                    // 可点的东西——而"执行入口必须固定、绝不整个消失"正是下面那条注释
                    // 已经写明的规则。
                    ForEach(startableCategories) { category in
                        aiStartControl(for: category)
                    }
                }
            } else if !library.isAIModelKeyConfigured {
                // 没配置 Key 也不能让开始按钮消失：它留在原位、置灰、说明原因，
                // 旁边紧跟着那个能解决问题的动作。
                ForEach(startableCategories) { category in
                    aiStartControl(for: category)
                }
                Button("设置并验证\(library.selectedAIModel.displayName)") {
                    showAISettings = true
                }
            } else if library.displayedAIFinalSelectionRunProgress.phase == .failed {
                ProgressView(value: library.displayedAIFinalSelectionRunProgress.fractionCompleted)
                Text("失败并停止 · 已评估 \(library.displayedAIFinalSelectionRunProgress.completedPhotoCount)/\(library.displayedAIFinalSelectionRunProgress.candidatePhotoCount) 张")
                    .font(Typography.detailNumeric)
                if let failure = library.displayedAIFinalSelectionRunProgress.failureMessage {
                    Text(failure)
                        .font(Typography.detail)
                        .foregroundStyle(.red)
                }
                HStack {
                    if let range = library.failedAIFinalSelectionPhotoRangeLabel {
                        Button("重试第 \(range) 张") {
                            library.retryFailedAIFinalSelectionRun()
                        }
                    }
                    Button("放弃", role: .destructive) { library.stopAIFinalSelectionRun() }
                }
            } else if library.isAIFinalSelectionRunActive {
                if let running = library.activeAIFinalSelectionCategory {
                    Text("正在为\(running.title)照片评分")
                        .font(Typography.detail)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: library.displayedAIFinalSelectionRunProgress.fractionCompleted)
                Text("\(library.displayedAIFinalSelectionRunProgress.phase.title) · \(library.displayedAIFinalSelectionRunProgress.completedPhotoCount)/\(library.displayedAIFinalSelectionRunProgress.candidatePhotoCount) 张")
                    .font(Typography.detailNumeric)
                if library.displayedAIFinalSelectionRunProgress.waitingSeconds > 0 {
                    Text("下一次请求约 \(library.displayedAIFinalSelectionRunProgress.waitingSeconds) 秒后发送")
                        .font(Typography.detailNumeric)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if library.displayedAIFinalSelectionRunProgress.phase == .paused {
                        Button("继续") { library.resumeAIFinalSelectionRun() }
                    } else {
                        Button("暂停") { library.pauseAIFinalSelectionRun() }
                    }
                    Button("停止", role: .destructive) { library.stopAIFinalSelectionRun() }
                }
            } else if library.displayedAIFinalSelectionRunProgress.phase == .completed {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "\(library.curationScope.title) AI评分已完成；网格已切到“已AI评分”，可逐张查看后采纳。"
                    )
                        .font(Typography.detail)
                        .foregroundStyle(.secondary)
                    ForEach(startableCategories) { category in
                        aiStartControl(for: category)
                    }
                }
            } else {
                // 执行入口必须固定：无论当前照片类型、目标数量或候选是否够用，
                // 开始按钮都在同一位置出现。不能开始时置灰并说明原因，绝不整个消失。
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(startableCategories) { category in
                        aiStartControl(for: category)
                    }
                }
            }

            if !library.isDemoModeActive {
                Text("\(library.selectedAIModel.providerAndModelDisplayName) · \(library.selectedAIPreviewSize.displayName)")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }

            if let usage = library.latestAIUsageMessage {
                Text(usage)
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.status")
        .accessibilityLabel("AI评分")
        .accessibilityValue(aiAccessibilityStatus)
    }

    /// "全部"视图下同时给出人物与风景两个入口；单类型视图下只给当前类型。
    private var startableCategories: [PhotoCurationCategory] {
        guard let category = library.curationScope.category else {
            return PhotoCurationCategory.allCases
        }
        return [category]
    }

    @ViewBuilder
    private func aiStartControl(for category: PhotoCurationCategory) -> some View {
        let availability = library.aiFinalSelectionAvailability(for: category)
        VStack(alignment: .leading, spacing: 3) {
            Button("开始\(category.title) AI评分（\(availability.candidatePhotoCount) 张）") {
                library.prepareAIFinalSelectionRun(for: category)
            }
            .disabled(!availability.canStart)
            .accessibilityIdentifier("ai.start.\(category.rawValue)")
            .firstCurationGuideTarget(
                library.demoScorableCategory == category,
                pointerSide: .trailing
            )
            .accessibilityHint(availability.blockedReason ?? "")

            if let reason = availability.blockedReason {
                Text(reason)
                    .font(Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var aiAccessibilityStatus: String {
        if library.isDemoModeActive {
            if library.isRunningDemoAIScoring {
                return String(
                    localized: "正在评估 · \(library.demoAIScoringCompletedPhotoCount)/\(library.displayedAIFinalSelectionRunProgress.candidatePhotoCount) 张"
                )
            }
            return String(localized: "示例筛选进行中")
        }
        if !library.isAIModelKeyConfigured {
            return String(localized: "设置并验证\(library.selectedAIModel.displayName)")
        }
        if library.displayedAIFinalSelectionRunProgress.phase == .failed {
            return String(
                localized: "失败并停止 · 已评估 \(library.displayedAIFinalSelectionRunProgress.completedPhotoCount)/\(library.displayedAIFinalSelectionRunProgress.candidatePhotoCount) 张"
            )
        }
        if library.isAIFinalSelectionRunActive {
            return String(
                localized: "\(library.displayedAIFinalSelectionRunProgress.phase.title) · \(library.displayedAIFinalSelectionRunProgress.completedPhotoCount)/\(library.displayedAIFinalSelectionRunProgress.candidatePhotoCount) 张"
            )
        }
        if library.displayedAIFinalSelectionRunProgress.phase == .completed {
            return String(localized: "AI评分已完成")
        }
        return String(localized: "等待运行")
    }

    private var photoGrid: some View {
        let localAICandidateIDs = library.localAestheticCandidatePhotoIDs
        let scopedPhotos = library.photos(in: library.curationScope)
        let filteredPhotos = gridFilter.photos(
            from: scopedPhotos,
            localAICandidateIDs: localAICandidateIDs
        )
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if library.isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在扫描")
                    }
                    Text(library.statusMessage)
                        .font(Typography.rowLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("photo.status")
                        .accessibilityLabel("项目状态")
                        .accessibilityValue(library.statusMessage)
                    Spacer(minLength: 0)
                }

                // 这一行全是控件，必须按中线对齐；顶对齐会让分段控件、菜单和计数各自错开几点。
                HStack(alignment: .center, spacing: 12) {
                    Picker(
                        "照片类型",
                        selection: $library.curationScope
                    ) {
                        ForEach(PhotoCurationScope.allCases) { scope in
                            Label(
                                scope.title,
                                systemImage: scope.systemImage
                            )
                            .tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .accessibilityIdentifier("photo.curation-scope")
                    .accessibilityLabel("照片类型")
                    .accessibilityValue(library.curationScope.title)
                    .firstCurationGuideTarget(
                        library.isCurationScopeGuideTarget,
                        pointerSide: .trailing,
                        cornerRadius: 6
                    )

                    Picker("照片筛选", selection: $gridFilter) {
                        ForEach(PhotoGridFilter.allCases) { filter in
                            Label(filter.title, systemImage: filter.systemImage)
                                .tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    // 920pt 最小宽度下也必须完整显示当前筛选名；截断成 "…" 等于这个控件不存在。
                    .frame(minWidth: 168, idealWidth: 180)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("photo.filter")
                    .accessibilityLabel("照片筛选")
                    .accessibilityValue(gridFilter.title)
                    .accessibilityHint("更改照片列表中显示的内容")
                    // 计数是"我刚才那一下筛掉了多少"的唯一反馈，不能小到看不清，
                    // 也不能因为宽度不够被截断——宁可挤压右侧空白。
                    Text("显示 \(filteredPhotos.count) / \(scopedPhotos.count)")
                        .font(Typography.rowValue)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("photo.visible-count")
                        .accessibilityLabel("显示照片数量")
                        .accessibilityValue("\(filteredPhotos.count) / \(scopedPhotos.count)")
                    Spacer(minLength: 0)
                }
            }
            .padding()
            .background(.bar)

            if library.firstCurationGuideStep != nil {
                Divider()
                FirstCurationGuideBar(
                    compact: false,
                    finishGuide: library.finishFirstCurationGuide,
                    startOwnPhotos: startOwnPhotosAfterGuide
                )
                Divider()
            }

            // 完成回执用浮层而不是占一行：它一旦参与竖向布局，
            // 就会和底部固定命令条抢高度，把"采纳"和"导出"挤出窗口。
            Group {
                if library.photos.isEmpty && !library.isScanning {
                    if library.activeProjectID == nil {
                        ContentUnavailableView(
                            "选择照片文件夹",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("支持 JPG、JPEG、PNG、WebP、HEIC、HEIF 和 TIFF。原图只在本机读取，不会被修改。")
                        )
                    } else {
                        // 已经打开了项目却一张也没有，说明目录里没有受支持的图片。
                        // 这时再显示“选择照片文件夹”会和用户刚做过的事情矛盾。
                        ContentUnavailableView(
                            "这个文件夹里没有受支持的照片",
                            systemImage: "folder.badge.questionmark",
                            description: Text("支持 JPG、JPEG、PNG、WebP、HEIC、HEIF 和 TIFF。子文件夹会一并扫描，隐藏文件会跳过。左上角可以新建另一个项目。")
                        )
                    }
                } else if filteredPhotos.isEmpty && !library.isScanning {
                    ContentUnavailableView {
                        Label(emptyFilterTitle, systemImage: gridFilter.systemImage)
                    } description: {
                        Text(emptyFilterDescription)
                    } actions: {
                        if gridFilter != .all {
                            Button("显示全部照片") { gridFilter = .all }
                                .accessibilityIdentifier("photo.filter.reset")
                        }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(filteredPhotos.enumerated()), id: \.element.id) { index, photo in
                                PhotoCard(
                                    photo: photo,
                                    isSelected: photo.id == library.selectedPhotoID,
                                    isLocalAICandidate: localAICandidateIDs.contains(photo.id),
                                    curationScope: library.curationScope,
                                    gridFilter: gridFilter,
                                    accessibilityIdentifier: "photo.card.\(index)",
                                    focusedPhotoID: $focusedPhotoID,
                                    select: {
                                        library.select(photo.id)
                                        focusedPhotoID = photo.id
                                    },
                                    preview: {
                                        library.select(photo.id)
                                        focusedPhotoID = photo.id
                                        openPhotoPreview(filteredPhotos)
                                    },
                                    moveFocus: { direction in
                                        movePhotoFocus(direction, from: index, in: filteredPhotos)
                                    }
                                )
                                .contextMenu {
                                    if !photo.aestheticRecommendations.isEmpty {
                                        Button("查看评分") {
                                            library.select(photo.id)
                                            openPhotoPreview(filteredPhotos)
                                        }
                                        Divider()
                                    }
                                    Button("保留") { library.mark(photoID: photo.id, as: .keep) }
                                    Button("淘汰") { library.mark(photoID: photo.id, as: .reject) }
                                    Button("恢复待定") { library.mark(photoID: photo.id, as: .undecided) }
                                    Divider()
                                    Menu("照片类型") {
                                        ForEach(
                                            PhotoCurationCategory.allCases
                                        ) { category in
                                            Button {
                                                library.setCurationCategory(
                                                    category,
                                                    for: photo.id
                                                )
                                            } label: {
                                                Label(
                                                    category.title,
                                                    systemImage:
                                                        photo.curationCategory
                                                            == category
                                                        ? "checkmark"
                                                        : category.systemImage
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let notice = library.visibleCompletionNotice {
                    completionBanner(notice)
                        .padding(12)
                }
            }

            if library.activeProject != nil {
                selectedPhotoInspector
                decisionActionBar
            }
        }
        // 可见集合只在这里推送一次。原来筛选、类型、候选池各监听各的、
        // 各自重算一遍可见列表，任何没被枚举到的原因（异步分析、评分结果到达）
        // 都会让选中项停在网格外。改成直接盯住渲染用的那份列表，覆盖全部原因。
        .onChange(of: filteredPhotos.map(\.id), initial: true) { _, visibleIDs in
            library.updateVisiblePhotos(visibleIDs)
        }
        .onChange(of: library.firstCurationGuideStep) { _, step in
            // 兜底：教学的每一步都要在网格里有可操作对象。
            // 任何让当前筛选变成 0 张的情况，都直接回到"全部照片"，不让教学卡在空网格上。
            if step != nil, gridFilter != .all {
                let visible = gridFilter.photos(
                    from: library.photos(in: library.curationScope),
                    localAICandidateIDs: library.localAestheticCandidatePhotoIDs
                )
                if visible.isEmpty {
                    gridFilter = .all
                }
            }
            switch step {
            case .viewScore:
                gridFilter = .aiScored
            case .acceptPeopleResults, .acceptSceneryResults:
                gridFilter = .aiScored
            default:
                break
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var selectedPhotoInspector: some View {
        // 多一层防御：不变量由 onChange 维护，而 onChange 在本帧渲染之后才触发，
        // 那一帧里选中项可能还没归位。检查条宁可不显示，也不能显示网格里没有的照片。
        if library.isSelectionVisible, let selected = library.selectedPhoto {
            selectedPhotoInspectorStrip(
                selected,
                visiblePhotos: gridFilter.photos(
                    from: library.photos(in: library.curationScope),
                    localAICandidateIDs: library.localAestheticCandidatePhotoIDs
                )
            )
        }
    }

    private var decisionActionBar: some View {
        ViewThatFits(in: .horizontal) {
            fullDecisionActionBarContent
                .fixedSize(horizontal: true, vertical: false)
            compactDecisionActionBarContent
        }
        .controlSize(.large)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decision.actions")
    }

    private var fullDecisionActionBarContent: some View {
        HStack(spacing: 10) {
            Button {
                library.undo()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .accessibilityIdentifier("decision.undo")
            .accessibilityLabel("撤销")
            .accessibilityHint("撤销上一次照片决定")
            .disabled(!library.canUndo)

            Divider().frame(height: 24)

            decisionButtons

            Spacer(minLength: 12)

            if library.pendingAIFinalSelectionAcceptanceCount > 0 {
                Button {
                    library.acceptPendingAIFinalSelection()
                } label: {
                    Label("采纳 \(library.pendingAIFinalSelectionAcceptanceCount) 张评分结果", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("decision.accept-ai")
                .accessibilityLabel("采纳 \(library.pendingAIFinalSelectionAcceptanceCount) 张评分结果")
                .firstCurationGuideTarget(
                    library.isAcceptGuideStep && gridFilter == .aiScored,
                    pointerSide: .leading
                )
            }

            Button {
                library.requestExport()
            } label: {
                Label(
                    "导出保留的 \(library.keepers.count) 张",
                    systemImage: "square.and.arrow.up"
                )
            }
            .disabled(!library.canExport)
            .accessibilityIdentifier("decision.export")
            .accessibilityLabel(
                "导出保留的人物 \(library.keepers(in: .people).count) 张、风景 \(library.keepers(in: .scenery).count) 张"
            )
            .firstCurationGuideTarget(
                library.firstCurationGuideStep == .exportCopies,
                pointerSide: .leading
            )
        }
    }

    /// 窄窗口下的自适应：只收缩次要控件（撤销改为图标、导出与采纳用短标签），
    /// 三个决定命令始终保持文字标签——它们必须和大图预览里的按钮长得一样，
    /// 否则用户的肌肉记忆会被窗口宽度打断。
    private var compactDecisionActionBarContent: some View {
        HStack(spacing: 8) {
            Button {
                library.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .accessibilityIdentifier("decision.undo")
            .accessibilityLabel("撤销")
            .accessibilityHint("撤销上一次照片决定")
            .help("撤销")
            .disabled(!library.canUndo)

            Divider().frame(height: 24)

            decisionButtons

            Spacer(minLength: 8)

            if library.pendingAIFinalSelectionAcceptanceCount > 0 {
                Button {
                    library.acceptPendingAIFinalSelection()
                } label: {
                    Label("采纳 \(library.pendingAIFinalSelectionAcceptanceCount) 张", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("decision.accept-ai")
                .accessibilityLabel("采纳 \(library.pendingAIFinalSelectionAcceptanceCount) 张评分结果")
                .help("采纳 \(library.pendingAIFinalSelectionAcceptanceCount) 张评分结果")
                .firstCurationGuideTarget(
                    library.isAcceptGuideStep && gridFilter == .aiScored,
                    pointerSide: .leading
                )
            }

            Button {
                library.requestExport()
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .disabled(!library.canExport)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("decision.export")
            .accessibilityLabel(
                "导出保留的人物 \(library.keepers(in: .people).count) 张、风景 \(library.keepers(in: .scenery).count) 张"
            )
            .help("导出保留的 \(library.keepers.count) 张")
            .firstCurationGuideTarget(
                library.firstCurationGuideStep == .exportCopies,
                pointerSide: .leading
            )
        }
    }

    /// 三个决定命令的唯一定义。网格底栏和大图预览共用它，保证两处外观完全一致。
    @ViewBuilder
    private var decisionButtons: some View {
        Button {
            library.markSelected(as: .undecided)
        } label: {
            Label("恢复待定", systemImage: "circle")
        }
        .disabled(!library.canDecideSelectedPhoto)
        .accessibilityIdentifier("decision.undecided")
        .accessibilityLabel("恢复待定")

        Button(role: .destructive) {
            library.markSelected(as: .reject)
        } label: {
            Label("淘汰", systemImage: "xmark.circle.fill")
        }
        .disabled(!library.canDecideSelectedPhoto)
        .accessibilityIdentifier("decision.reject")
        .accessibilityLabel("淘汰")

        Button {
            library.markSelected(as: .keep)
        } label: {
            Label("保留", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(!library.canDecideSelectedPhoto)
        .accessibilityIdentifier("decision.keep")
        .accessibilityLabel("保留")
    }

    private var emptyFilterTitle: String {
        switch gridFilter {
        case .aiCandidates: String(localized: "暂无待评分照片")
        case .aiScored: String(localized: "暂无已评分照片")
        default: String(localized: "没有\(gridFilter.title)照片")
        }
    }

    private var emptyFilterDescription: String {
        if gridFilter == .aiCandidates, library.isAnalyzing {
            return String(localized: "本地分析完成后，候选照片会自动出现在这里。")
        }
        if gridFilter == .aiScored {
            return String(localized: "完成任一组 AI评分后，每张有效评分照片都会显示在这里。")
        }
        return String(localized: "切换到“全部照片”查看完整照片集。")
    }

    private func openPhotoPreview(_ visiblePhotos: [PhotoItem]) {
        guard let first = visiblePhotos.first else { return }
        // 选中项必须在传入列表里，否则预览的 currentIndex 为 nil，
        // 上一张/下一张会全部禁用，看起来像预览坏了。
        if !visiblePhotos.contains(where: { $0.id == library.selectedPhotoID }) {
            library.select(first.id)
        }
        previewPhotoIDs = visiblePhotos.map(\.id)
        showPhotoPreview = true
    }

    private func selectedPhotoSummary(_ photo: PhotoItem) -> String? {
        var summaries: [String] = []
        if let similarityGroup = photo.similarityGroup {
            summaries.append(
                String(
                    localized: "相似照片 \(similarityGroup.position)/\(similarityGroup.count)"
                )
            )
        }
        if let risk = photo.technicalQuality?.primaryRisk {
            summaries.append(risk.title)
        }
        if let recommendation = photo.primaryAestheticRecommendation {
            summaries.append(String(localized: "AI \(recommendation.score) 分"))
        }
        return summaries.isEmpty
            ? String(localized: "双击可查看大图")
            : summaries.formatted(.list(type: .and))
    }

    /// 选中照片的检查条：紧贴命令条上方，让"选中了哪张"和"能对它做什么"处在同一处。
    ///
    /// 这些控件原先混在网格工具栏里，与照片类型、筛选、计数这些网格级控件同排，
    /// 一行里混了两种作用域，且在最小窗口宽度下会截断成 "demo…"。
    /// 原来那个决定下拉菜单已删除：它和下方命令条的三个按钮是同一动作的第二个可见入口。
    private func selectedPhotoInspectorStrip(
        _ photo: PhotoItem,
        visiblePhotos: [PhotoItem]
    ) -> some View {
        HStack(spacing: 10) {
            ThumbnailView(url: photo.url)
                .frame(width: 44, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(photo.filename)
                    .font(Typography.rowLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let summary = selectedPhotoSummary(photo) {
                    Text(summary)
                        .font(Typography.detail)
                        .foregroundStyle(
                            photo.technicalQuality?.risks.isEmpty == false
                                ? .orange
                                : .secondary
                        )
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                openPhotoPreview(visiblePhotos)
            } label: {
                Label(
                    photo.aestheticRecommendations.isEmpty
                        ? String(localized: "预览")
                        : String(localized: "查看评分"),
                    systemImage: photo.aestheticRecommendations.isEmpty
                        ? "eye"
                        : "chart.bar.xaxis"
                )
            }
            .fixedSize(horizontal: true, vertical: false)
            .help(
                photo.aestheticRecommendations.isEmpty
                    ? String(localized: "预览")
                    : String(localized: "查看评分")
            )
            .accessibilityLabel(
                photo.aestheticRecommendations.isEmpty
                    ? String(localized: "预览")
                    : String(localized: "查看评分")
            )
            .accessibilityIdentifier("photo.preview")
            .firstCurationGuideTarget(
                library.firstCurationGuideStep == .viewScore,
                pointerSide: .leading
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photo.details")
    }

    private func movePhotoFocus(
        _ direction: MoveCommandDirection,
        from currentIndex: Int,
        in visiblePhotos: [PhotoItem]
    ) {
        let offset: Int
        switch direction {
        case .left, .up:
            offset = -1
        case .right, .down:
            offset = 1
        @unknown default:
            return
        }

        let nextIndex = currentIndex + offset
        guard visiblePhotos.indices.contains(nextIndex) else { return }
        let nextPhoto = visiblePhotos[nextIndex]
        library.select(nextPhoto.id)
        focusedPhotoID = nextPhoto.id
    }

    /// 完成态的可见回执。只陈述结果和下一步，不重复底部命令条里已有的命令。
    ///
    /// 它是浮在网格上方的卡片，不占竖向布局：一旦参与布局就会和底部固定命令条抢高度，
    /// 窗口不够高时把“采纳”“导出”整条挤出可视区域。
    @ViewBuilder
    private func completionBanner(_ notice: CurationCompletionNotice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(Typography.rowLabelActive)
                Text(notice.message)
                    .font(Typography.detail)
                    .foregroundStyle(.secondary)
                    // 浮层高度必须有上限，长文案不能无限撑高把照片挡光。
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            if case let .export(url) = notice.kind {
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .accessibilityIdentifier("completion.reveal-export")
            }
            Button("知道了") {
                library.dismissCompletionNotice()
            }
            .accessibilityIdentifier("completion.dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.green.opacity(0.45))
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("completion.notice")
        .accessibilityLabel(notice.title)
        .accessibilityValue(notice.message)
    }

    private var exportConfirmationMessage: String {
        let people = library.keepers(in: .people).count
        let scenery = library.keepers(in: .scenery).count
        let base = String(
            localized: "将复制人物 \(people) 张、风景 \(scenery) 张，并放入两个子目录；原照片不会被移动、删除或修改。"
        )
        guard let notice = library.exportTargetDeviationNotice else { return base }
        return "\(base)\n\(notice)"
    }

    private var aiFinalSelectionConfirmationButtonTitle: String {
        guard let plan = library.pendingAIFinalSelectionRunPlan else {
            return String(localized: "开始")
        }
        return String(localized: "发送 \(plan.candidatePhotoCount) 张并开始")
    }

    /// 发送确认只说明"用哪个模型给多少张什么照片打分"。
    /// endpoint、预览尺寸在侧栏 AI评分区常驻可见，完整的请求、排序、重试与费用规则在"帮助与支持"。
    private var aiFinalSelectionConfirmationMessage: String {
        guard let plan = library.pendingAIFinalSelectionRunPlan else { return "" }
        if library.isDemoModeActive {
            return String(
                localized:
                    "离线示例：用内置结果为 \(plan.candidatePhotoCount) 张\(library.pendingAIFinalSelectionCategory.title)照片打分，不联网、不读取 Keychain、不消耗额度。"
            )
        }
        return String(
            localized:
                "将使用\(library.pendingAIFinalSelectionModel.apiModelID)为 \(plan.candidatePhotoCount) 张\(library.pendingAIFinalSelectionCategory.title)照片打分。"
        )
    }


}

/// 侧栏入口按钮的统一排版：固定宽度的图标列 + 统一字号字重。
///
/// SF Symbols 的固有宽度各不相同（`folder.badge.plus` 明显比 `gearshape` 宽），
/// 直接用 `Label` 的话，每个按钮的图标中心和文字起点都会差几个点；
/// 五个按钮竖排在一起时这种参差非常显眼。
/// 字号也显式固定：`.borderedProminent` 会把标题加粗，和相邻的 `.bordered` 不一致。
private struct SidebarEntryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .imageScale(.medium)
                .frame(width: 18, alignment: .center)
            configuration.title
                .font(Typography.entryLabel)
        }
    }
}

private struct IdentifiedBadge {
    let view: AnyView
}

private struct PhotoCard: View {
    let photo: PhotoItem
    let isSelected: Bool
    let isLocalAICandidate: Bool
    /// 当前网格的作用域与筛选：用来判断哪些徽章在这个上下文里是恒等信息。
    let curationScope: PhotoCurationScope
    let gridFilter: PhotoGridFilter
    let accessibilityIdentifier: String
    let focusedPhotoID: FocusState<String?>.Binding
    let select: () -> Void
    let preview: () -> Void
    let moveFocus: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailView(url: photo.url, fillsFrame: false)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        if photo.decision != .undecided {
                            Label(photo.decision.title, systemImage: photo.decision.symbolName)
                                .font(Typography.badge)
                                .foregroundStyle(decisionColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(.regularMaterial, in: Capsule())
                                .padding(7)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if showsCategoryBadge, let category = photo.curationCategory {
                            Label(
                                category.title,
                                systemImage: category.systemImage
                            )
                            .font(Typography.badge)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(
                                .regularMaterial,
                                in: Capsule()
                            )
                            .padding(7)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(informationBadges.enumerated()), id: \.offset) { _, badge in
                                badge.view
                            }
                        }
                        .padding(7)
                    }
            }
            .padding(8)
            .background(cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(photo.filename)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded(preview)
        )
        .focusable()
        .focused(focusedPhotoID, equals: photo.id)
        .onKeyPress(.leftArrow) {
            moveFocus(.left)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveFocus(.right)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveFocus(.up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveFocus(.down)
            return .handled
        }
        .onKeyPress(.space) {
            preview()
            return .handled
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(photo.filename)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("选择此照片；双击可查看大图，也可使用保留、淘汰或恢复待定操作")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 卡片上最多显示两个信息徽章。
    ///
    /// 优先级：AI 分数 > 技术风险 > 相似照片位置 > 待评分。
    /// 当前筛选已经蕴含的信息不再重复出现——例如筛到"待AI评分"时不再给每张挂"待评分"。
    private var informationBadges: [IdentifiedBadge] {
        var badges: [IdentifiedBadge] = []
        if let badgeText = aestheticRecommendationBadge(for: photo) {
            badges.append(IdentifiedBadge(view: AnyView(AestheticRecommendationBadge(text: badgeText))))
        }
        if let risk = photo.technicalQuality?.primaryRisk {
            badges.append(IdentifiedBadge(view: AnyView(RiskBadge(text: risk.title))))
        }
        if let similarityGroup = photo.similarityGroup {
            badges.append(
                IdentifiedBadge(
                    view: AnyView(
                        GroupBadge(
                            text: String(
                                localized: "相似 \(similarityGroup.position)/\(similarityGroup.count)"
                            )
                        )
                    )
                )
            )
        }
        if isLocalAICandidate, showsCandidatePoolBadge {
            badges.append(IdentifiedBadge(view: AnyView(CandidatePoolBadge(text: String(localized: "待评分")))))
        }
        return Array(badges.prefix(2))
    }

    /// 已经按人物或风景筛选时，每张卡再写一次同样的类型没有信息量。
    private var showsCategoryBadge: Bool {
        curationScope == .all
    }

    /// 筛选本身就是"待AI评分"时，不必给每张卡再挂一个"待评分"。
    private var showsCandidatePoolBadge: Bool {
        gridFilter != .aiCandidates
    }

    private var decisionColor: Color {
        switch photo.decision {
        case .keep: .green
        case .reject: .red
        case .undecided: .white
        }
    }

    private var cardBackground: Color {
        switch photo.decision {
        case .keep: .green.opacity(0.12)
        case .reject: .red.opacity(0.12)
        case .undecided: .primary.opacity(0.04)
        }
    }

    private var accessibilityValue: String {
        var details = [String(localized: "决定：\(photo.decision.title)")]
        if let category = photo.curationCategory {
            details.append(
                String(localized: "照片类型：\(category.title)")
            )
        }
        if let similarityGroup = photo.similarityGroup {
            details.append(String(localized: "相似照片：第 \(similarityGroup.position) / \(similarityGroup.count) 张"))
        }
        if let risk = photo.technicalQuality?.primaryRisk {
            details.append(risk.title)
        }
        if isLocalAICandidate {
            details.append(String(localized: "待评分"))
        }
        if let recommendation = aestheticRecommendationBadge(for: photo) {
            details.append(recommendation)
        }
        return details.formatted(.list(type: .and))
    }
}

private struct CandidatePoolBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.badge)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.teal.opacity(0.9), in: Capsule())
    }
}

private func aestheticRecommendationBadge(for photo: PhotoItem) -> String? {
    guard let recommendation = photo.primaryAestheticRecommendation else {
        return nil
    }
    return String(localized: "AI \(recommendation.score) 分")
}

private struct RiskBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.badge)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.9), in: Capsule())
    }
}

private struct AestheticRecommendationBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.badge)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.purple.opacity(0.88), in: Capsule())
    }
}

private struct GroupBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.badge)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
    }
}

private struct ThumbnailView: View {
    let url: URL
    /// 卡片需要看清构图，必须保留长宽比；检查条里的 44×32 小图只作辨认用，填充更整齐。
    var fillsFrame: Bool = true
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                if fillsFrame {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: url) {
            image = nil
            image = await ThumbnailCache.shared.image(for: url)
        }
    }
}
