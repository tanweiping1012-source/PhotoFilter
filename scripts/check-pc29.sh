#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-29 检查失败：%s\n' "$1" >&2
  exit 1
}

onboarding="Sources/PhotoCurator/OnboardingView.swift"
view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
content="Sources/PhotoCurator/ContentView.swift"
preview="Sources/PhotoCurator/PhotoPreviewView.swift"
demo="Sources/PhotoCurator/DemoModeLibrary.swift"

rg -q 'static let currentVersion = 3' "$onboarding" ||
  fail "新版引导没有升级版本"
rg -q 'completed-onboarding-version-v3' "$onboarding" ||
  fail "新版引导缺少独立偏好键"
if rg -q 'OnboardingStep|moveForward|moveBackward' "$onboarding"; then
  fail "旧四页轮播逻辑仍然存在"
fi
rg -q '从一段旅程中，选出真正值得保留的照片' "$onboarding" ||
  fail "场景首页缺少旅行照片整理目标"
rg -q 'Label\("体验一次完整筛选"' "$onboarding" ||
  fail "场景首页缺少完整体验入口"
rg -q 'Label\("选择我的照片"' "$onboarding" ||
  fail "场景首页缺少真实照片入口"

# 步骤顺序必须和真实主链路一致：本地分析 → 按类型 AI评分 → 采纳 → 导出。
# 旧版把"手动保留"排在 AI评分 之前，教出来的因果是反的——真实流程里"采纳"
# 做的事就是 decision = .keep，保留是产出而不是评分的入场券。
for step in \
  analyzePhotos \
  choosePeople \
  runPeopleAIScoring \
  viewScore \
  acceptPeopleResults \
  switchSceneryAndScore \
  acceptSceneryResults \
  exportCopies \
  completed; do
  rg -q "case $step" "$onboarding" ||
    fail "教学状态缺少：$step"
done
rg -q 'static let taskCount = 8' "$onboarding" ||
  fail "教学任务数量不是 8"

rg -q 'let startingPhotos: \[PhotoItem\]' "$demo" ||
  fail "离线样例缺少未评分起点"
rg -q 'startingPhotos: startingPhotos' "$demo" ||
  fail "未评分起点没有进入样例会话"
# 只断言“教学起点来自未评分的 startingPhotos”，不锁定具体赋值写法，
# 否则任何一次无关重构都会让门禁误报。真正的行为由 DemoModeLibraryTests 覆盖。
rg -q 'session\.startingPhotos' "$view_model" ||
  fail "进入教学时仍直接载入评分结果"
rg -q 'aiFinalSelectionPhotoIDsByCategory = \[:\]' "$view_model" ||
  fail "进入教学时仍直接载入 AI 推荐结果"
rg -q 'func startDemoAIScoring' "$view_model" ||
  fail "缺少用户主动触发的离线评分"
rg -q 'Task\.sleep\(for: \.milliseconds\(450\)\)' "$view_model" ||
  fail "离线评分没有逐批演示"
rg -q 'applyDemoAIScoringBatch' "$view_model" ||
  fail "离线评分没有按批写入结果"

demo_methods="$(
  sed -n \
    '/func startDemoAIScoring/,/func exitDemoMode/p' \
    "$view_model"
)"
if printf '%s\n' "$demo_methods" |
  rg -n 'URLSession|AIProviderKeyStore|SecItem|https?://'; then
  fail "离线评分路径不得访问网络或 Keychain"
fi

rg -q 'FirstCurationGuideBar' "$content" ||
  fail "照片网格没有接入任务条"
rg -q 'FirstCurationGuideBar' "$preview" ||
  fail "大图预览没有接入任务条"
for identifier in \
  first-curation.guide \
  guide.start-own-photos \
  guide.finish \
  guide.exit; do
  rg -Fq "\"$identifier\"" "$preview" ||
    fail "任务条缺少无障碍标识：$identifier"
done
# 教学不再有"打开大图"这一步：本地分析之后直接进入按类型评分。
if rg -q 'recordDemoPhotoPreviewOpened' "$preview" "$view_model"; then
  fail "教学仍保留已废弃的打开大图步骤"
fi
rg -q 'func startDemoAnalysisPacing' "$view_model" ||
  fail "示例没有走本地分析这一步，而它是真实用户最先看到的一屏"
rg -q 'recordDemoScoreReviewFinished' "$preview" ||
  fail "查看评分没有推进教学"
rg -q 'confirmDemoScoreReview' "$preview" "$view_model" ||
  fail "查看评分缺少明确继续命令"
# 看完评分后关掉大图就是"我看过了"，不再需要一个只在教学期间存在的"继续"按钮。
rg -Uq 'onDismiss[^\n]*\n?[^\n]*library\.confirmDemoScoreReview\(\)|library\.confirmDemoScoreReview\(\)' "$content" ||
  fail "关闭大图没有推进查看评分这一步"
rg -q 'firstCurationGuideStep = \.exportCopies' "$view_model" ||
  fail "采纳结果没有推进到导出"
rg -q 'firstCurationGuideStep = \.completed' "$view_model" ||
  fail "导出成功没有完成教学"

rg -q 'testDemoAIScoringRunsOfflineRequestWindows' \
  Tests/PhotoCuratorTests/DemoModeLibraryTests.swift ||
  fail "缺少离线评分传输窗口测试"
rg -q 'XCTAssertEqual\(viewModel\.firstCurationGuideStep, \.choosePeople\)' \
  Tests/PhotoCuratorTests/DemoModeLibraryTests.swift ||
  fail "缺少教学初始状态测试"
rg -q 'XCTAssertTrue\(viewModel\.canExport\)' \
  Tests/PhotoCuratorTests/DemoModeLibraryTests.swift ||
  fail "缺少完整体验收敛到可导出测试"

for screenshot in \
  docs/interaction-screenshots/first-curation-entry-zh-Hans.png \
  docs/interaction-screenshots/first-curation-task-zh-Hans-920x640.png \
  docs/interaction-screenshots/first-curation-ai-progress-zh-Hans-920x640.png \
  docs/interaction-screenshots/first-curation-score-review-zh-Hans.png \
  docs/interaction-screenshots/first-curation-entry-en.png \
  docs/interaction-screenshots/first-curation-task-en-920x640.png \
  docs/interaction-screenshots/first-curation-ai-progress-en-920x640.png \
  docs/interaction-screenshots/first-curation-score-review-en.png; do
  [[ -s "$screenshot" ]] ||
    fail "缺少教学原型图：$screenshot"
done

for document in \
  AGENTS.md \
  docs/product/ONBOARDING.md \
  docs/product/OVERVIEW.md \
  docs/privacy/APP_REVIEW_DEMO.md \
  docs/engineering/TASKS.md; do
  rg -q '第一次筛选|完整筛选|First Curation' "$document" ||
    fail "$document 未记录新版教学"
done

catalog="Resources/Localizable.xcstrings"
key_count="$(jq '.strings | length' "$catalog")"
english_count="$(
  jq '[.strings[] | select(.localizations.en.stringUnit.value != null)] | length' \
    "$catalog"
)"
stale_count="$(
  jq '[.strings[] | select(.extractionState == "stale")] | length' "$catalog"
)"
[[ "$key_count" == "$english_count" ]] ||
  fail "String Catalog 有 $((key_count - english_count)) 个键缺少英文"
[[ "$stale_count" == 0 ]] ||
  fail "String Catalog 仍有 $stale_count 个 stale 键"

rg -A2 '## PC-29 第一次筛选任务教学' docs/engineering/TASKS.md |
  rg -q '\*\*状态：已完成\*\*' ||
  fail "PC-29 尚未标记完成"

printf 'PC-29 检查通过：场景首页、八步任务、离线分类评分、双语和原型图一致。\n'
