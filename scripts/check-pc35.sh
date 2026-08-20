#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-35 检查失败：%s\n' "$1" >&2
  exit 1
}

target="Sources/PhotoCurator/FirstCurationGuideTarget.swift"
content="Sources/PhotoCurator/ContentView.swift"
preview="Sources/PhotoCurator/PhotoPreviewView.swift"
view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
tests="Tests/PhotoCuratorTests/DemoModeLibraryTests.swift"
project="PhotoCurator.xcodeproj/project.pbxproj"
screenshots=(
  "docs/interaction-screenshots/first-curation-spotlight-card-zh-Hans-920x640.png:1840 x 1280"
  "docs/interaction-screenshots/first-curation-spotlight-keep-zh-Hans.png:1920 x 1360"
  "docs/interaction-screenshots/first-curation-spotlight-keep-phase-b-zh-Hans.png:1920 x 1360"
  "docs/interaction-screenshots/first-curation-score-continue-zh-Hans.png:1920 x 1360"
  "docs/interaction-screenshots/first-curation-show-scoring-picks-zh-Hans-920x640.png:1840 x 1280"
  "docs/interaction-screenshots/first-curation-show-scoring-picks-en-920x640.png:1840 x 1280"
  "docs/interaction-screenshots/first-curation-finish-zh-Hans-920x640.png:1840 x 1280"
  "docs/interaction-screenshots/first-curation-finish-en-920x640.png:1840 x 1280"
)

rg -q 'FirstCurationGuideTarget.swift in Sources' "$project" ||
  fail "聚焦组件未加入 Xcode target"
rg -q 'Color\.red' "$target" ||
  fail "聚焦边框不是红色"
rg -q 'strokeBorder\(' "$target" ||
  fail "聚焦主边框没有贴合控件内部"
if rg -q 'withAnimation|repeatForever|isAnimating|scaleEffect|padding\(-[0-9]|cornerRadius \+ 3' "$target"; then
  fail "聚焦层仍有动画或向外扩张，可能产生跨区域漂移"
fi
rg -q 'hand\.point\.(left|right|down)\.fill' "$target" ||
  fail "聚焦缺少固定小指针"
rg -q 'var offset: CGSize' "$target" ||
  fail "聚焦指针没有使用固定坐标"
rg -q 'allowsHitTesting\(false\)' "$target" ||
  fail "聚焦 overlay 可能拦截真实控件"

for step in \
  choosePeople \
  inspectPhoto \
  keepPhoto \
  runAIScoring \
  switchToScenery \
  viewScore \
  acceptResults \
  exportCopies; do
  rg -q "firstCurationGuideStep.*\\.$step|firstCurationGuideStep == \\.$step|== \\.$step" \
    "$content" "$preview" ||
    fail "教学步骤缺少聚焦目标：$step"
done

rg -q 'guide\.show-scoring-picks' "$preview" ||
  fail "确认结果步骤缺少显示 AI 评分结果的直接按钮"
rg -Uq 'case \.acceptResults:[[:space:]\n]*gridFilter = \.all' "$content" ||
  fail "确认结果步骤没有先清除遗留筛选"
rg -Uq 'showScoringPicks:[[:space:]\n]*\{[[:space:]\n]*gridFilter = \.aiScored' "$content" ||
  fail "显示 AI 评分结果按钮没有切换到评分列表"
rg -q 'gridFilter == \.aiScored' "$content" ||
  fail "显示 AI 评分结果后没有转移到采纳按钮"
rg -q 'guide\.confirm-score-review' "$preview" ||
  fail "评分详情步骤缺少明确继续按钮"
rg -q 'onChange\(of: library\.firstCurationGuideStep\)' "$preview" ||
  fail "大图没有监听教学步骤切换"
rg -q 'shouldClosePhotoPreview' "$preview" \
  Sources/PhotoCurator/OnboardingView.swift ||
  fail "第 5 步没有自动返回照片网格"
rg -Uq 'Label\([[:space:]\n]*"评分已查看，继续"' "$preview" ||
  fail "评分详情继续按钮文案不明确"
rg -Uq 'Label\([[:space:]\n]*"显示 AI 评分结果"' "$preview" ||
  fail "确认结果直接按钮文案不明确"
rg -Uq 'Label\([[:space:]\n]*"结束新手引导"' "$preview" ||
  fail "完成状态缺少结束新手引导主按钮"
rg -q 'buttonStyle\(\.borderedProminent\)' "$preview" ||
  fail "结束新手引导不是主按钮"
rg -q 'accessibilityIdentifier\("guide\.finish"\)' "$preview" ||
  fail "结束按钮缺少稳定无障碍标识"

rg -q 'func recordDemoExportCompleted' "$view_model" ||
  fail "导出完成没有统一推进教学状态"
rg -q 'func finishFirstCurationGuide' "$view_model" ||
  fail "缺少正常结束教学命令"
rg -q 'recordDemoExportCompleted\(\)' "$view_model" ||
  fail "真实导出成功没有推进完成状态"
rg -q 'viewModel\.recordDemoExportCompleted\(\)' "$tests" ||
  fail "缺少导出完成状态测试"
rg -q 'shouldClosePhotoPreview' "$tests" ||
  fail "缺少第 5 步自动关闭大图回归测试"
rg -q 'viewModel\.finishFirstCurationGuide\(\)' "$tests" ||
  fail "缺少结束主按钮状态测试"
rg -q 'XCTAssertFalse\(viewModel\.isDemoModeActive\)' "$tests" ||
  fail "缺少结束后退出示例断言"

for document in \
  docs/product/ONBOARDING.md \
  docs/engineering/TASKS.md; do
  rg -q '红色|红框' "$document" ||
    fail "$document 未记录固定红框聚焦"
  rg -q '结束新手引导' "$document" ||
    fail "$document 未记录完成主按钮"
done

for screenshot_spec in "${screenshots[@]}"; do
  screenshot="${screenshot_spec%%:*}"
  expected_size="${screenshot_spec#*:}"
  [[ -s "$screenshot" ]] ||
    fail "缺少视觉验收快照：$screenshot"
  file "$screenshot" | rg -Fq "PNG image data, $expected_size" ||
    fail "视觉验收快照尺寸不正确：$screenshot"
done

printf 'PC-35 检查通过：八步固定聚焦、条件目标切换和结束新手引导主按钮一致。\n'
