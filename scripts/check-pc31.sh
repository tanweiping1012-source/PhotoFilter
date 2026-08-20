#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-31 检查失败：%s\n' "$1" >&2
  exit 1
}

progress="Sources/PhotoCurator/AIFinalSelectionRun.swift"
view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
content="Sources/PhotoCurator/ContentView.swift"
preview="Sources/PhotoCurator/PhotoPreviewView.swift"
privacy="Sources/PhotoCurator/PrivacyInformationView.swift"

rg -q 'var completedPhotoCount = 0' "$progress" ||
  fail "运行状态缺少已评估照片数"
rg -q 'Double\(completedPhotoCount\) / Double\(candidatePhotoCount\)' \
  "$progress" ||
  fail "进度条仍未按照片数计算"
rg -q 'func photoRange\(forGroupAt index: Int\)' "$progress" ||
  fail "计划无法把内部请求映射为照片范围"

rg -Uq 'completedPhotoCount =\s+photoRange\.upperBound' "$view_model" ||
  fail "通过校验后没有累计照片进度"
rg -q 'failedAIFinalSelectionPhotoRangeLabel' "$view_model" "$content" ||
  fail "失败恢复没有显示照片范围"
rg -q 'demoAIScoringCompletedPhotoCount' "$view_model" "$preview" ||
  fail "离线教学仍未按照片计数"

# 入口改为按类型渲染（"全部"视图下同时给出人物与风景），标题仍必须带上该类型的待评分张数。
rg -Fq '开始\(category.title) AI评分（\(availability.candidatePhotoCount) 张）' "$content" ||
  fail "开始操作没有显示总照片数"
rg -q 'completedPhotoCount.*candidatePhotoCount.*张' "$content" ||
  fail "主状态没有按照片显示"
# 发送边界只在隐私页写一次。
# 这条断言原本要求帮助页也出现一遍——两页各写一份，就是重复的来源，而且
# 它们已经漂移过：帮助页写"模型、张数和照片类型"，隐私页写"供应商、模型、
# 预览尺寸和照片数量"，弹窗实际只有前者。发送什么数据属于数据披露，
# 归隐私页；帮助页只讲怎么跑、跑多久、花多少钱。
rg -q '每次请求发送 2–5 张' "$privacy" ||
  fail "隐私说明仍未按每次请求照片数表达"
if rg -q '2–5 张' Sources/PhotoCurator/SupportInformationView.swift; then
  fail "帮助页又开始复述发送边界，它只应出现在隐私页"
fi

# 完成回执必须跟着项目走：它说的是"这个项目刚发生了什么"。
# 作为全局单值时，真实项目评分完成后打开示例，示例第 1 步头上会顶着真实项目的
# "风景 AI评分完成"，点"知道了"还会把真实项目的回执一并消掉。
# 回执只由真实 AI 评分或导出产生，两条路径在单元测试里都不可达，所以按结构断言。
rg -q 'let completionNotice: CurationCompletionNotice\?' "$view_model" ||
  fail "项目快照没有携带完成回执"
rg -q 'completionNotice: completionNotice,' "$view_model" ||
  fail "保存项目快照时没有带上完成回执"
rg -q 'completionNotice = snapshot\.completionNotice' "$view_model" ||
  fail "恢复项目快照时没有恢复该项目自己的完成回执"
demo_notice_cleared="$(
  awk '/func startDemoMode/,/func completeDemoAIScoringImmediately/' "$view_model" |
    rg -c 'completionNotice = nil' || true
)"
[[ "${demo_notice_cleared:-0}" -ge 1 ]] ||
  fail "进入示例筛选时没有清空上一个项目的完成回执"

# 用量文案只代表本轮。不在任务开始时清掉旧文案的话，新任务 0/N 期间会继续显示
# 上一类的数字，等第一批返回再被本轮小计覆盖——用户看到的就是一次用量倒退。
run_start_cleared="$(
  awk '/func submitConfirmedAIFinalSelectionRun/,/aiFinalSelectionRunContext = AIFinalSelectionRunContext/' \
    "$view_model" | rg -c 'latestAIUsageMessage = nil' || true
)"
[[ "${run_start_cleared:-0}" == "1" ]] ||
  fail "新的 AI 任务开始时没有清空上一轮用量文案"
rg -q '本轮：输入' "$progress" ||
  fail "用量文案没有说明这是本轮用量"
if rg -q '累计：输入' "$progress"; then
  fail "用量数字每轮清零，文案不能自称累计"
fi

for source in "$content" "$preview" "$privacy"; do
  if rg -n \
    'String\(localized: "[^"]*批|Text\("[^"]*批|Label\("[^"]*批|Button\("[^"]*批|detail: "[^"]*批' \
    "$source"; then
    fail "$source 仍暴露批次概念"
  fi
done

catalog="Resources/Localizable.xcstrings"
if jq -e '.strings | keys[] | select(test("批"))' "$catalog" >/dev/null; then
  fail "String Catalog 仍包含用户可见批次文案"
fi

rg -q 'testRunProgressUsesCompletedPhotosInsteadOfRequestCount' \
  Tests/PhotoCuratorTests/AIFinalSelectionRunTests.swift ||
  fail "缺少照片进度比例测试"
rg -q 'photoRange\(forGroupAt: 6\), 31\.\.\.35' \
  Tests/PhotoCuratorTests/AIFinalSelectionRunTests.swift ||
  fail "缺少不均匀照片范围测试"
rg -q 'demoAIScoringCompletedPhotoCount, 8' \
  Tests/PhotoCuratorTests/DemoModeLibraryTests.swift ||
  fail "缺少离线教学照片进度测试"

for document in \
  AGENTS.md \
  docs/ai/SCORING.md \
  docs/product/OVERVIEW.md \
  docs/product/ONBOARDING.md \
  docs/privacy/PRIVACY_POLICY.md \
  docs/engineering/TASKS.md; do
  rg -q '照片数|照片数量|已评估照片|评估.*张' "$document" ||
    fail "$document 未记录照片进度"
done

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

rg -A2 '## PC-31 AI评分照片进度' docs/engineering/TASKS.md |
  rg -q '\*\*状态：已完成\*\*' ||
  fail "PC-31 尚未标记完成"

printf 'PC-31 检查通过：AI评分进度、重试和离线教学均按照片数量表达。\n'
