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
                "将复制人物 \(library.selectionTargets.people) 张、风景 \(library.selectionTargets.scenery) 张，并放入两个子目录；原照片不会被移动、删除或修改。"
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
            PhotoPreviewView(photoIDs: previewPhotoIDs)
                .environmentObject(library)
        }
        .onChange(of: library.activeProjectID) { _, _ in
            showPhotoPreview = false
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
                        .font(.title2.weight(.bold))
                    Text("每个日期文件夹是一项独立任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    library.chooseFolder()
                } label: {
                    Label("新建筛选项目", systemImage: "folder.badge.plus")
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(library.isProjectNavigationLocked)
                    .accessibilityIdentifier("sidebar.onboarding")

                    Button {
                        showAISettings = true
                    } label: {
                        Label("AI评分设置", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sidebar.ai-settings")
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
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

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
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.support")
                .accessibilityHint("查看常见问题和复制非敏感诊断信息")

                Button {
                    showPrivacyInformation = true
                } label: {
                    Label("隐私与数据", systemImage: "hand.raised")
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
                            .font(.subheadline.weight(isActive ? .semibold : .regular))
                            .lineLimit(2)
                        Text(projectStatusText(project))
                            .font(.caption2)
                            .foregroundStyle(project.accessState == .needsAuthorization ? .orange : .secondary)
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
                    .font(.headline)
                ForEach(PhotoCurationCategory.allCases) { category in
                    selectionTargetRow(category)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("selection.targets")

            if let analysisLabel = library.analysisProgressLabel {
                VStack(alignment: .leading, spacing: 5) {
                    Text(analysisLabel).font(.caption)
                    ProgressView(value: library.analysisProgress)
                        .accessibilityLabel("本地分析进度")
                        .accessibilityValue(analysisLabel)
                }
                .accessibilityIdentifier("analysis.progress")
            }

            if library.keeperDiversityConflictCount > 0 {
                Label("已有 \(library.keeperDiversityConflictCount) 组重复照片被同时保留，请每组只留一张。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
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
                    .font(.subheadline.weight(.medium))
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
                    library.isAIFinalSelectionRunActive
                        || library.isDemoModeActive
                )
                Text("\(target) 张")
                    .font(.caption.monospacedDigit())
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
            .font(.caption2.monospacedDigit())
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
                    .font(.headline)
            }

            if !library.localAestheticCandidatePhotoIDs.isEmpty {
                Text("待评分 \(library.localAestheticCandidatePhotoIDs.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if library.isDemoModeActive {
                Label("离线教学", systemImage: "graduationcap")
                    .foregroundStyle(Color.accentColor)
                Text("不联网，不读取 Keychain，不消耗 API 额度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if library.isRunningDemoAIScoring {
                    ProgressView(
                        value: library.displayedAIFinalSelectionRunProgress
                            .fractionCompleted
                    )
                    Text(
                        "正在评估 · \(library.demoAIScoringCompletedPhotoCount)/\(library.displayedAIFinalSelectionRunProgress.candidatePhotoCount) 张"
                    )
                    .font(.caption.monospacedDigit())
                }
            } else if !library.isAIModelKeyConfigured {
                Text("\(library.selectedAIModel.providerAndModelDisplayName) · \(library.selectedAIPreviewSize.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("设置并验证\(library.selectedAIModel.displayName)") {
                    showAISettings = true
                }
            } else if library.displayedAIFinalSelectionRunProgress.phase == .failed {
                ProgressView(value: library.displayedAIFinalSelectionRunProgress.fractionCompleted)
                Text("失败并停止 · 已评估 \(library.displayedAIFinalSelectionRunProgress.completedPhotoCount)/\(library.displayedAIFinalSelectionRunProgress.candidatePhotoCount) 张")
                    .font(.caption.monospacedDigit())
                if let failure = library.displayedAIFinalSelectionRunProgress.failureMessage {
                    Text(failure)
                        .font(.caption)
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
                ProgressView(value: library.displayedAIFinalSelectionRunProgress.fractionCompleted)
                Text("\(library.displayedAIFinalSelectionRunProgress.phase.title) · \(library.displayedAIFinalSelectionRunProgress.completedPhotoCount)/\(library.displayedAIFinalSelectionRunProgress.candidatePhotoCount) 张")
                    .font(.caption.monospacedDigit())
                if library.displayedAIFinalSelectionRunProgress.waitingSeconds > 0 {
                    Text("下一次请求约 \(library.displayedAIFinalSelectionRunProgress.waitingSeconds) 秒后发送")
                        .font(.caption.monospacedDigit())
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
                        "\(library.curationScope.title) AI评分已完成，可用“评分优先”查看结果。"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if library.canPrepareAIFinalSelectionRun {
                        Button("重新运行") { library.prepareAIFinalSelectionRun() }
                    }
                }
            } else if library.curationScope == .all {
                Text("先在照片类型中选择人物或风景，再运行该类型的 AI评分。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let plan = library.aiFinalSelectionRunPlan {
                Button("开始\(library.curationScope.title) AI评分（\(plan.candidatePhotoCount) 张）") {
                    library.prepareAIFinalSelectionRun()
                }
                .disabled(!library.canPrepareAIFinalSelectionRun)
            } else {
                Text("分析完成并解决重复保留冲突后，即可开始 AI评分。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !library.isDemoModeActive, library.isAIModelKeyConfigured {
                Text("\(library.selectedAIModel.providerAndModelDisplayName) · \(library.selectedAIPreviewSize.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let usage = library.latestAIUsageMessage {
                Text(usage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.status")
        .accessibilityLabel("AI评分")
        .accessibilityValue(aiAccessibilityStatus)
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
            localAICandidateIDs: localAICandidateIDs,
            aiFinalSelectionIDs: library.aiFinalSelectionPhotoIDs
        )
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if library.isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在扫描")
                    }
                    if let analysisLabel = library.analysisProgressLabel {
                        ProgressView(value: library.analysisProgress)
                            .frame(width: 92)
                            .accessibilityLabel("本地分析进度")
                            .accessibilityValue(analysisLabel)
                    }
                    Text(library.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("photo.status")
                        .accessibilityLabel("项目状态")
                        .accessibilityValue(library.statusMessage)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 12) {
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
                    .disabled(library.isAIFinalSelectionRunActive)
                    .accessibilityIdentifier("photo.curation-scope")
                    .accessibilityLabel("照片类型")
                    .accessibilityValue(library.curationScope.title)
                    .firstCurationGuideTarget(
                        library.firstCurationGuideStep
                            == .choosePeople
                            || library.firstCurationGuideStep
                                == .switchToScenery,
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
                    .frame(minWidth: 128)
                    .accessibilityIdentifier("photo.filter")
                    .accessibilityLabel("照片筛选")
                    .accessibilityValue(gridFilter.title)
                    .accessibilityHint("更改照片列表中显示的内容")
                    .padding(4)
                    Text("显示 \(filteredPhotos.count) / \(scopedPhotos.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("photo.visible-count")
                        .accessibilityLabel("显示照片数量")
                        .accessibilityValue("\(filteredPhotos.count) / \(scopedPhotos.count)")
                    Spacer(minLength: 0)
                    if let selected = library.selectedPhoto {
                        ViewThatFits(in: .horizontal) {
                            selectedPhotoControls(
                                selected,
                                visiblePhotos: filteredPhotos,
                                compact: false
                            )
                            .fixedSize(horizontal: true, vertical: false)
                            selectedPhotoControls(
                                selected,
                                visiblePhotos: filteredPhotos,
                                compact: true
                            )
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("photo.details")
                    }
                }
            }
            .padding()
            .background(.bar)

            if library.firstCurationGuideStep != nil {
                Divider()
                FirstCurationGuideBar(
                    compact: false,
                    showScoringPicks: {
                        gridFilter = .aiSelected
                    },
                    isShowingScoringPicks:
                        gridFilter == .aiSelected,
                    finishGuide: library.finishFirstCurationGuide,
                    startOwnPhotos: startOwnPhotosAfterGuide
                )
                Divider()
            }

            if library.photos.isEmpty && !library.isScanning {
                ContentUnavailableView(
                    "选择照片文件夹",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("第一版支持 JPG、JPEG、PNG 和 WebP。原图只在本机读取。")
                )
            } else if filteredPhotos.isEmpty && !library.isScanning {
                ContentUnavailableView(
                    emptyFilterTitle,
                    systemImage: gridFilter.systemImage,
                    description: Text(emptyFilterDescription)
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(filteredPhotos.enumerated()), id: \.element.id) { index, photo in
                            PhotoCard(
                                photo: photo,
                                isSelected: photo.id == library.selectedPhotoID,
                                isLocalAICandidate: localAICandidateIDs.contains(photo.id),
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
                            .firstCurationGuideTarget(
                                (
                                    library.firstCurationGuideStep
                                        == .inspectPhoto
                                        || library.firstCurationGuideStep
                                            == .viewScore
                                )
                                    && photo.id
                                        == library.selectedPhotoID,
                                pointerSide: .trailing,
                                cornerRadius: 12
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

            if library.activeProject != nil {
                decisionActionBar
            }
        }
        .onChange(of: gridFilter) { _, newFilter in
            let visiblePhotos = newFilter.photos(
                from: library.photos(in: library.curationScope),
                localAICandidateIDs:
                    library.localAestheticCandidatePhotoIDs,
                aiFinalSelectionIDs:
                    library.aiFinalSelectionPhotoIDs
            )
            selectFirstVisiblePhoto(from: visiblePhotos)
        }
        .onChange(of: library.curationScope) { _, newScope in
            let visiblePhotos = gridFilter.photos(
                from: library.photos(in: newScope),
                localAICandidateIDs:
                    library.localAestheticCandidatePhotoIDs,
                aiFinalSelectionIDs:
                    library.aiFinalSelectionPhotoIDs
            )
            selectFirstVisiblePhoto(from: visiblePhotos)
        }
        .onChange(of: localAICandidateIDs) { _, _ in
            guard gridFilter == .aiCandidates else { return }
            let candidates = gridFilter.photos(
                from: library.photos(in: library.curationScope),
                localAICandidateIDs: library.localAestheticCandidatePhotoIDs
            )
            selectFirstVisiblePhoto(from: candidates)
        }
        .onChange(of: library.aiFinalSelectionPhotoIDs) { _, finalSelectionIDs in
            guard gridFilter == .aiSelected else { return }
            let selections = gridFilter.photos(
                from: library.photos(in: library.curationScope),
                localAICandidateIDs: library.localAestheticCandidatePhotoIDs,
                aiFinalSelectionIDs: finalSelectionIDs
            )
            selectFirstVisiblePhoto(from: selections)
        }
        .onChange(of: library.firstCurationGuideStep) { _, step in
            switch step {
            case .viewScore:
                gridFilter = .aiScored
                let scoredPhotos = PhotoGridFilter.aiScored.photos(
                    from: library.photos(in: library.curationScope),
                    localAICandidateIDs:
                        library.localAestheticCandidatePhotoIDs,
                    aiFinalSelectionIDs:
                        library.aiFinalSelectionPhotoIDs
                )
                selectFirstVisiblePhoto(from: scoredPhotos)
            case .acceptResults:
                gridFilter = .all
                selectFirstVisiblePhoto(
                    from: library.photos(in: library.curationScope)
                )
            default:
                break
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

            Button {
                library.markSelected(as: .undecided)
            } label: {
                Label("恢复待定", systemImage: "circle")
            }
            .disabled(library.selectedPhoto == nil || library.isAIFinalSelectionRunActive)
            .accessibilityIdentifier("decision.undecided")
            .accessibilityLabel("恢复待定")

            Button(role: .destructive) {
                library.markSelected(as: .reject)
            } label: {
                Label("淘汰", systemImage: "xmark.circle.fill")
            }
            .disabled(library.selectedPhoto == nil || library.isAIFinalSelectionRunActive)
            .accessibilityIdentifier("decision.reject")
            .accessibilityLabel("淘汰")

            Button {
                library.markSelected(as: .keep)
            } label: {
                Label("保留", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(library.selectedPhoto == nil || library.isAIFinalSelectionRunActive)
            .accessibilityIdentifier("decision.keep")
            .accessibilityLabel("保留")

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
                    library.firstCurationGuideStep == .acceptResults
                        && gridFilter == .aiSelected,
                    pointerSide: .leading
                )
            }

            Button {
                library.requestExport()
            } label: {
                Label(
                    "导出人物与风景 \(library.targetSelectionCount) 张",
                    systemImage: "square.and.arrow.up"
                )
            }
            .disabled(!library.canExport)
            .accessibilityIdentifier("decision.export")
            .accessibilityLabel(
                "导出人物 \(library.selectionTargets.people) 张、风景 \(library.selectionTargets.scenery) 张"
            )
            .firstCurationGuideTarget(
                library.firstCurationGuideStep == .exportCopies,
                pointerSide: .leading
            )
        }
    }

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

            Button {
                library.markSelected(as: .undecided)
            } label: {
                Image(systemName: "circle")
            }
            .disabled(library.selectedPhoto == nil || library.isAIFinalSelectionRunActive)
            .accessibilityIdentifier("decision.undecided")
            .accessibilityLabel("恢复待定")
            .help("恢复待定")

            Button(role: .destructive) {
                library.markSelected(as: .reject)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .disabled(library.selectedPhoto == nil || library.isAIFinalSelectionRunActive)
            .accessibilityIdentifier("decision.reject")
            .accessibilityLabel("淘汰")
            .help("淘汰")

            Button {
                library.markSelected(as: .keep)
            } label: {
                Image(systemName: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(library.selectedPhoto == nil || library.isAIFinalSelectionRunActive)
            .accessibilityIdentifier("decision.keep")
            .accessibilityLabel("保留")
            .help("保留")

            Spacer(minLength: 8)

            if library.pendingAIFinalSelectionAcceptanceCount > 0 {
                Button {
                    library.acceptPendingAIFinalSelection()
                } label: {
                    Label("采纳 \(library.pendingAIFinalSelectionAcceptanceCount) 张评分结果", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("decision.accept-ai")
                .accessibilityLabel("采纳 \(library.pendingAIFinalSelectionAcceptanceCount) 张评分结果")
                .firstCurationGuideTarget(
                    library.firstCurationGuideStep == .acceptResults
                        && gridFilter == .aiSelected,
                    pointerSide: .leading
                )
            }

            Button {
                library.requestExport()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(!library.canExport)
            .accessibilityIdentifier("decision.export")
            .accessibilityLabel(
                "导出人物 \(library.selectionTargets.people) 张、风景 \(library.selectionTargets.scenery) 张"
            )
            .help("导出人物与风景 \(library.targetSelectionCount) 张")
            .firstCurationGuideTarget(
                library.firstCurationGuideStep == .exportCopies,
                pointerSide: .leading
            )
        }
    }

    private var emptyFilterTitle: String {
        switch gridFilter {
        case .aiCandidates: String(localized: "暂无待评分照片")
        case .aiScored: String(localized: "暂无已评分照片")
        case .aiSelected: String(localized: "暂无评分优先照片")
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
        if gridFilter == .aiSelected {
            return String(localized: "完成整轮 AI评分后，最终胜出照片会显示在这里。")
        }
        return String(localized: "切换到“全部照片”查看完整照片集。")
    }

    private func selectFirstVisiblePhoto(from visiblePhotos: [PhotoItem]) {
        guard let firstVisible = visiblePhotos.first else { return }
        if !visiblePhotos.contains(where: { $0.id == library.selectedPhotoID }) {
            library.select(firstVisible.id)
        }
    }

    private func openPhotoPreview(_ visiblePhotos: [PhotoItem]) {
        guard !visiblePhotos.isEmpty, library.selectedPhoto != nil else {
            return
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

    private func selectedPhotoControls(
        _ photo: PhotoItem,
        visiblePhotos: [PhotoItem],
        compact: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if compact {
                Text(photo.filename)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: 125, alignment: .trailing)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(photo.filename)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let summary = selectedPhotoSummary(photo) {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(
                                photo.technicalQuality?.risks.isEmpty == false
                                    ? .orange
                                    : .secondary
                            )
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 210, alignment: .trailing)
            }

            Button {
                openPhotoPreview(visiblePhotos)
            } label: {
                if compact {
                    if photo.aestheticRecommendations.isEmpty {
                        Image(systemName: "eye")
                    } else {
                        Label("评分", systemImage: "chart.bar.xaxis")
                    }
                } else {
                    Label(
                        photo.aestheticRecommendations.isEmpty
                            ? String(localized: "预览")
                            : String(localized: "查看评分"),
                        systemImage: photo.aestheticRecommendations.isEmpty
                            ? "eye"
                            : "chart.bar.xaxis"
                    )
                }
            }
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

            if compact {
                Menu {
                    selectedPhotoDecisionMenu()
                } label: {
                    Image(systemName: photo.decision.symbolName)
                }
                .help(photo.decision.title)
                .accessibilityLabel(photo.decision.title)
            } else {
                Menu(photo.decision.title) {
                    selectedPhotoDecisionMenu()
                }
            }
        }
    }

    @ViewBuilder
    private func selectedPhotoDecisionMenu() -> some View {
        Button("保留") { library.markSelected(as: .keep) }
        Button("淘汰") { library.markSelected(as: .reject) }
        Button("恢复待定") { library.markSelected(as: .undecided) }
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

    private var aiFinalSelectionConfirmationButtonTitle: String {
        guard let plan = library.pendingAIFinalSelectionRunPlan else {
            return String(localized: "开始")
        }
        return String(localized: "发送 \(plan.candidatePhotoCount) 张并开始")
    }

    private var aiFinalSelectionConfirmationMessage: String {
        guard let plan = library.pendingAIFinalSelectionRunPlan else { return "" }
        let model = library.pendingAIFinalSelectionModel
        let size = library.pendingAIFinalSelectionPreviewSize
        let category = plan.groups.first?.scope.category
        let categoryTitle = category?.title
            ?? String(localized: "当前类型")
        return String(localized: "将使用\(model.providerAndModelDisplayName)和\(size.displayName)预览，通过 \(model.endpointHost) 独立评估 \(plan.candidatePhotoCount) 张\(categoryTitle)照片；全部完成后只在\(categoryTitle)内按统一分数排序，取前 \(plan.targetWinnerCount) 张。每次请求只发送 2–5 张同类型、无元数据 JPEG，不发送原图、文件名、路径或 EXIF/GPS；请求至少间隔 60 秒，预计最短约 \(plan.estimatedMinimumMinutes) 分钟。更大的预览可能增加上传量、等待时间和供应商费用；格式异常会自动重试 1 次，仍失败时会停在当前照片范围供你重试或放弃。结果不会自动标记为保留。")
    }
}

private struct PhotoCard: View {
    let photo: PhotoItem
    let isSelected: Bool
    let isLocalAICandidate: Bool
    let accessibilityIdentifier: String
    let focusedPhotoID: FocusState<String?>.Binding
    let select: () -> Void
    let preview: () -> Void
    let moveFocus: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailView(url: photo.url)
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        Label(photo.decision.title, systemImage: photo.decision.symbolName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(decisionColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(7)
                    }
                    .overlay(alignment: .topLeading) {
                        if let category = photo.curationCategory {
                            Label(
                                category.title,
                                systemImage: category.systemImage
                            )
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(
                                .ultraThinMaterial,
                                in: Capsule()
                            )
                            .padding(7)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let similarityGroup = photo.similarityGroup {
                                GroupBadge(text: String(localized: "相似 \(similarityGroup.position)/\(similarityGroup.count)"))
                            }
                            if let risk = photo.technicalQuality?.primaryRisk {
                                RiskBadge(text: risk.title)
                            }
                            if isLocalAICandidate {
                                CandidatePoolBadge(text: String(localized: "待评分"))
                            }
                            if let badgeText = aestheticRecommendationBadge(for: photo) {
                                AestheticRecommendationBadge(text: badgeText)
                            }
                        }
                        .padding(7)
                    }
                Text(photo.filename)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
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
            .font(.caption2.weight(.semibold))
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
            .font(.caption2.weight(.semibold))
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
            .font(.caption2.weight(.semibold))
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
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
    }
}

private struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
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
