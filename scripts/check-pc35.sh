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
# 指针的偏移是固定 24pt，前提是目标周围留得出这段空间。侧栏里满宽的一行两边
# 都没有，指针会压在面板边界上。自动执行的步骤也不该出现"点这里"的手。
rg -q 'case noPointer' "$target" ||
  fail "聚焦缺少无指针模式，满宽目标只能画框"
rg -Uq 'firstCurationGuideStep == \.analyzePhotos,[[:space:]\n]*pointerSide: \.noPointer' "$content" ||
  fail "本地分析这一步不该画手形指针：它是自动执行的，且目标两侧没有指针空间"
rg -q 'var offset: CGSize' "$target" ||
  fail "聚焦指针没有使用固定坐标"
rg -q 'allowsHitTesting\(false\)' "$target" ||
  fail "聚焦 overlay 可能拦截真实控件"

# 每一步都必须有聚焦目标。
#
# 多数条件收在 ViewModel 里而不是直接写在视图上：ContentView 那个大 VStack
# 再多几个布尔运算，Swift 类型检查就会超时。所以这里对源和视图两头都断言。
for step in analyzePhotos viewScore exportCopies; do
  rg -q "firstCurationGuideStep == \.$step" "$content" ||
    fail "教学步骤缺少聚焦目标：$step"
done
rg -q 'var isCurationScopeGuideTarget' "$view_model" ||
  fail "缺少 choosePeople / switchSceneryAndScore 的聚焦条件"
rg -q 'library\.isCurationScopeGuideTarget' "$content" ||
  fail "照片类型分段控件没有承接教学指针"
rg -q 'var isAcceptGuideStep' "$view_model" ||
  fail "缺少 acceptPeopleResults / acceptSceneryResults 的聚焦条件"
rg -q 'library\.isAcceptGuideStep' "$content" ||
  fail "采纳按钮没有承接教学指针"
# 第 1 步虽然是自动执行的，但红框的作用是"看这里"而不是"点这里"：
# 没有它，用户不知道该盯着哪儿等分析结束。
# 本地分析进度只允许有一条：工具栏和侧栏各画一条时，同一件事说了两遍，
# 而旁边的状态文字已经在说同样的话。带张数的那条留在侧栏。
# 教学进行中不得再显示完成回执横幅：任务条已经在讲下一步，回执讲的是另一个
# 下一步，两条指令同屏竞争；回执还是浮层，会盖住网格顶排照片。
rg -q 'var visibleCompletionNotice' "$view_model" ||
  fail "缺少教学期间隐藏完成回执的判定"
rg -q 'library\.visibleCompletionNotice' "$content" ||
  fail "完成回执横幅没有在教学期间隐藏"
if rg -q 'if let notice = library\.completionNotice \{' "$content"; then
  fail "完成回执横幅又直接读取了未过滤的回执"
fi

analysis_bars="$(rg -c 'value: library\.analysisProgress' "$content" || true)"
[[ "${analysis_bars:-0}" == "1" ]] ||
  fail "本地分析进度条有 ${analysis_bars:-0} 条，应只保留侧栏那一条"

# 教学必须驱动真实控件。
#
# 以前第 4、6、7 步各挂了一个只在教学期间渲染的按钮（演示 AI评分 / 评分已查看，
# 继续 / 显示 AI 评分结果）。用户走完八步，学到的是一套用完就消失的界面：真实的
# AI评分 入口在侧栏，教学从头到尾一次都没指向过侧栏，于是回到真实流程时，
# "保留"之后眼前最显眼的前进按钮变成了"导出"。
if rg -q 'guide\.run-ai-scoring|guide\.show-scoring-picks|guide\.confirm-score-review' \
  "$preview" "$content"; then
  fail "教学又出现了只在教学期间存在的专属按钮"
fi
rg -q 'library\.demoScorableCategory == category' "$content" ||
  fail "侧栏 AI评分 入口没有承接教学指针"
# 入口必须在示例模式里也画出来：只把可用性打开、视图分支不渲染按钮，
# 教学会在第 4 步直接卡死——没有任何可点的东西。
demo_branch_entry="$(
  awk '/if library\.isDemoModeActive \{/,/\} else if !library\.isAIModelKeyConfigured \{/' \
    "$content" | rg -c 'aiStartControl\(for: category\)' || true
)"
[[ "${demo_branch_entry:-0}" -ge 1 ]] ||
  fail "示例模式的侧栏没有渲染 AI评分 启动入口，教学会卡在第 4 步"
rg -q 'func demoScorableCategory|var demoScorableCategory' "$view_model" ||
  fail "示例模式没有按类型开放真实的 AI评分 入口"
rg -q 'startDemoAIScoring\(for: category\)' "$view_model" ||
  fail "示例评分没有走真实的发送确认框"
rg -Uq 'case \.acceptPeopleResults, \.acceptSceneryResults:[[:space:]\n]*gridFilter = \.aiScored' "$content" ||
  fail "确认结果步骤应停在已AI评分列表，推荐结果就在那份列表里"
rg -q 'onChange\(of: library\.firstCurationGuideStep\)' "$preview" ||
  fail "大图没有监听教学步骤切换"
rg -q 'shouldClosePhotoPreview' "$preview" \
  Sources/PhotoCurator/OnboardingView.swift ||
  fail "第 5 步没有自动返回照片网格"
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
