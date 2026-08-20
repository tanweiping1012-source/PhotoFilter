# 代码结构

一个 SwiftUI + Swift Concurrency 的 macOS App，约 13k 行源码 + 27 个测试文件。
没有第三方依赖：图像走 ImageIO / Core Graphics，本地识别走 Vision，网络走 URLSession。

两套构建系统并存，**新增源文件时两边都要加**：

- `Package.swift`：`swift build` / `swift test` 用，跑单元测试和门禁
- `PhotoCurator.xcodeproj`：产出真正的 `.app`（沙箱、entitlements、Info.plist、资源打包）

## 一张照片的旅程

```
选择文件夹
   ↓  PhotoAnalysisPipeline.imageURLs        递归枚举，过滤扩展名与隐藏文件
   ↓  PhotoLibraryViewModel.startScan        立刻建出 PhotoItem 数组 → 网格可见（约 0.1s）
   ↓  PhotoAnalysisPipeline.analyze(urls:)   后台并行，每张只解码一次 1024px
   │     ├─ PhotoMetadataReader              EXIF 拍摄时间（含时区偏移）
   │     ├─ PerceptualHasher                 64×64 灰度感知指纹
   │     ├─ TechnicalQualityAnalyzer         512px 上的清晰度 / 反差 / 曝光
   │     └─ PhotoCategoryClassifier          一个 Vision handler 跑完 5 个请求 → 人物 / 风景
   ↓  PhotoAnalysisMerger.applying           分批合回主 actor，绝不覆盖人工决定
   ↓  SimilarityGrouper                      感知指纹聚成相似家族（时间只做辅助）
   ↓  TechnicalQualityAnalyzer.assigningSharpnessRisks   家族内相对判定清晰度风险
   ↓  LocalCandidateRanker                   家族内排出本地技术顺序
   ↓  LocalAestheticCandidatePlanner         每类生成待评分池（每家族最多一个代表）
   ↓  AIFinalSelectionRunPlanner             候选切成 2–5 张的传输窗口
   ↓  AestheticReviewClient（按协议分发）     发送无元数据 JPEG，严格校验响应
   ↓  AIFinalSelectionRunValidator           类别内全局排序 → AI 推荐保留
   ↓  ExportService.copyCategorized          只复制，写 selection.json / csv
```

## 模块地图

### 分析与筛选（纯函数为主，最容易测）

| 文件 | 职责 |
|---|---|
| `PhotoAnalysisPipeline.swift` | 单次解码流水线 + 并行调度 + 目录枚举。**改分析性能先看这里** |
| `LuminanceThumbnailReader.swift` | 从已解码 CGImage 生成灰度栅格（指纹用正方形，清晰度用保长宽比） |
| `PerceptualHasher.swift` | 64 位灰度感知指纹与汉明距离 |
| `TechnicalQualityAnalyzer.swift` | 清晰度 / 反差 / 曝光；清晰度风险按同组相对判定 |
| `PeopleSubjectClassifier.swift` | Vision 证据采集 + 人物主题判定规则 |
| `SimilarityGrouper.swift` | 相似家族聚类 |
| `CandidateFamilyIndex.swift` | 家族查询与冲突检测 |
| `LocalCandidateRanker.swift` | 家族内本地技术排序 |
| `LocalAestheticCandidatePlanner.swift` | 待评分池的容量收敛与时间线抽样 |
| `PhotoMetadataReader.swift` | EXIF 拍摄时间与时区偏移 |
| `PhotoAnalysisMerger.swift` | 分析结果合并，保护人工决定 |

### AI评分

| 文件 | 职责 |
|---|---|
| `AIModelCatalog.swift` | 品牌 / 模型描述、endpoint、能力标记、全局偏好存储 |
| `AestheticReviewContract.swift` | 请求构造、响应校验、提示词 |
| `AIFinalSelectionRun.swift` | 运行计划、重试退避策略、结果校验与排序 |
| `*AestheticReviewClient.swift` | 各协议适配器（方舟 / MiniMax / Anthropic / OpenAI-compatible） |
| `AIReviewPreviewEncoder.swift` | 内存中生成无元数据 JPEG |
| `AIProviderKeyStore.swift` | 每供应商独立 Keychain 条目 |
| `AIReviewURLSession`（在 `AIModelCatalog.swift`） | AI 专用 ephemeral session：无磁盘缓存 / Cookie / 凭据，超时 180s |
| `AIModelDiscoveryService.swift` / `AIModelConnectionVerifier.swift` | 账号模型发现与真实图片连接验证 |

### 状态与界面

| 文件 | 职责 |
|---|---|
| `PhotoLibraryViewModel.swift` | **2.4k 行的中枢**：项目、扫描、分析、持久化、安全作用域、AI 运行、演示模式全在这里 |
| `ContentView.swift` | 主窗口：侧栏 + 网格 + 底部命令条 |
| `PhotoPreviewView.swift` | 只读大图检查 |
| `AISettingsView.swift` | 全局 AI 设置 |
| `OnboardingView.swift` / `DemoModeLibrary.swift` | 首次引导与离线教学 |
| `ThumbnailCache.swift` | 缩略图解码与内存缓存 |

### 持久化与导出

| 文件 | 职责 |
|---|---|
| `ProjectPersistence.swift` | 项目目录、security-scoped bookmark、schema 迁移 |
| `ExportService.swift` | 分类复制导出与清单生成 |

## 必须守住的不变量

改动涉及以下任何一条时，一定要补测试并跑 `scripts/check.sh`：

1. **原图只读。** 任何代码路径都不得写入、移动、改名用户目录中的文件。`RealLibraryEndToEndTests` 会逐文件比对大小与修改时间。
2. **人工决定优先。** 后台分析结果合并时不得覆盖 keep / reject 和用户的分类纠正。
3. **发送边界。** 只发送用户确认过尺寸的无元数据 JPEG 与匿名 `photo_id`，绝不发原图、文件名、路径、EXIF。
4. **Key 隔离。** API Key 只进对应供应商的 Keychain 条目，不进 UserDefaults、项目状态、日志、导出。
5. **家族唯一代表。** 同一相似家族最多一张进入待评分池与最终结果。
6. **契约校验。** 非法 AI 响应不得参与排序或展示。
7. **执行入口固定。** AI评分开始按钮永远渲染在同一位置；不能开始时置灰并给出可执行的原因，绝不隐藏。
   被禁用的入口旁边必须有原因文本——写在只有点击才触发的 `statusMessage` 里等于没写。
8. **候选池缓存与照片状态同步。** 任何改变照片、决定、分类、目标或分析结果的路径都必须调用
   `invalidateCandidatePlans()`，否则界面会一直沿用分析期间读到的空候选池。
9. **AI 请求不落盘。** 走 `AIReviewURLSession.shared`，不得改回 `URLSession.shared`——
   共享 session 挂着磁盘 URLCache、Cookie 与凭据存储。
10. **选中项必须可见。** `updateVisiblePhotos(_:)` 是可见集合的唯一来源；
    `reconcileSelection()` 保证 `selectedPhotoID` 要么是它的成员、要么为 nil。
    新增任何改变网格内容的路径时不必单独接线——界面只盯 `filteredPhotos` 一处推送。
11. **附加界面不占主布局高度。** 完成回执用浮层；任何新增的固定行都可能把底部命令条挤出窗口。
    文件面板用 `beginSheetModal(for:)`，不用 `runModal()`。
12. **导出目录在项目目录之外。** 否则既往只读的原图目录写入，又会让下一次递归扫描
    把副本当成新照片。

## 改动落点速查

| 你想做的事 | 落点 |
|---|---|
| 让扫描更快 | `PhotoAnalysisPipeline`（解码尺寸、并发路数、批大小） |
| 调整人物/风景判定 | `PeopleSubjectEvaluator` 的阈值常量 + `PeopleSubjectClassifierTests` |
| 调整相似判定松紧 | `SimilarityGrouper.assigningGroups` 的距离参数 |
| 调整候选池大小 | `LocalAestheticCandidatePlanner` 的容量常量 |
| 接一个新供应商 | 优先复用 `OpenAICompatibleAestheticReviewClient`，只在 `AIModelCatalog` 加条目；新协议才写新适配器 |
| 改请求节奏 / 重试 | `AIReviewConfiguration` + `AIFinalSelectionRetryPolicy` |
| 改导出结构 | `ExportService.copyCategorized` + `SelectionRulesTests` |
| 改评分期间的可操作范围 | `AIFinalSelectionRunLock` + `PhotoLibraryViewModel.isPhotoLockedByActiveAIFinalSelectionRun` |
| 改完成后的落点或回执 | `completeAIFinalSelectionRun` 里的 `curationScope` / `completionNotice` + `ContentView.completionBanner` |

## 发布路径

```bash
scripts/archive-app.sh          # Release 归档
scripts/package-dmg.sh          # 通用 DMG（校验 arm64 + x86_64 与签名）
```

`scripts/*.sh` 必须保持可执行位（git mode 100755）：release 脚本一旦掉成 644，
文档里写的命令会直接 `Permission denied`。
推送 `v*` 标签由 `.github/workflows/release.yml` 跑完整门禁、打 DMG 并创建草稿 Release。
`dist/` 已被 `.gitignore` 排除，构建产物只作为 Release 资产存在。

## 性能基线

在 M 系列 8 核 / 16GB、475 张 40MP JPEG（9.4GB）上实测：

| 指标 | 数值 |
|---|---|
| 网格可见 | 0.1 s |
| 完整本地分析 | 约 52 s（并行 6 路，约 0.06 s/张） |
| 单张串行成本 | 0.244 s（其中一次 1024px 解码 + 一次 Vision） |

回归检查（默认跳过，需显式提供照片目录）：

```bash
PHOTO_BENCH_DIR=/path/to/photos swift test --filter "Benchmark|RealLibraryEndToEnd"
```

## 已知技术债

- `PhotoLibraryViewModel` 是个上帝对象，演示模式的分支散落在生产路径里。拆分方向：
  `ProjectCoordinator` / `AnalysisPipeline` / `AIScoringRunner` / `DemoLibrarySource`，
  其中演示模式应实现为独立的 library source，而不是 `if isDemoModeActive`。
- `scripts/check-pc*.sh` 是基于 ripgrep 的文本断言，锁定实现细节而非行为，重构时容易误报。
  方向是保留隐私 / 只读导出 / Key 隔离这类真不变量，其余转成单元测试。
- 感知指纹是 8×8 aHash，对裁剪与旋转脆弱；后续里程碑换向量相似度。
