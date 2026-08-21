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

# 说明必须贴着它描述的进度条。此前"正在评估第 N 张，共 M 张…"写在顶部的项目状态行里，
# 和侧栏进度条隔了大半个窗口，用户要在两处之间来回找，才能把两个数字对上。
rg -q 'var activity: String\?' "$progress" ||
  fail "运行状态没有承载"此刻在做什么""
rg -q 'ai\.run\.activity' "$content" ||
  fail "进度条下方没有渲染当前动作说明"
# 只取首次出现：phase.title 在无障碍摘要里还会再出现一次，取最后一次会把顺序判反。
awk '/displayedAIFinalSelectionRunProgress.phase.title/{if (!count) count = NR}
     /ai\.run\.activity/{if (!activity) activity = NR}
     /library.pauseAIFinalSelectionRun\(\)/{if (!pause) pause = NR}
     END{exit (count && activity && pause && count < activity && activity < pause) ? 0 : 1}' \
  "$content" ||
  fail "当前动作说明没有紧跟在进度计数之后"

# 顶部那行 statusMessage 曾经是个通用容器，塞过 60 条消息：扫描、分析、决定回执、
# AI 进度、导出、授权失败共用一行，绝大多数时候在说用户已经从别处知道的事。
# 逐条查证后它一条都不剩：空状态和空网格有 ContentUnavailableView，导出结果有完成
# 回执横幅（还带"在访达中显示"），AI 运行阶段有侧栏进度块，操作没生效有紧挨动作的弹窗，
# 教学该说的话归任务条。这个容器已整体移除——它不该以任何形式回来。
if rg -q '@Published.*var statusMessage' "$view_model"; then
  fail "通用状态行又回来了；新消息应就近显示，而不是共用一行"
fi
if rg -q 'photo\.status' "$content"; then
  fail "通用状态行的界面残留仍在"
fi

rg -q '@Published var actionFailureMessage: String\?' "$view_model" ||
  fail "缺少紧挨动作的失败反馈"
rg -q 'actionFailureMessage' "$content" ||
  fail "动作失败反馈没有在界面上呈现"

# 改类型会清空两个类型的全部 AI评分结果，而且不进撤销栈。必须先问再动手。
rg -q 'pendingCurationCategoryChange' "$view_model" "$content" ||
  fail "改照片类型清除已付费评分前没有确认"
rg -q '改变类型会清除已有 AI评分' "$content" ||
  fail "确认框没有说清会清除什么"

# 逐张进度不得再回到顶部的项目状态行。顶部只留一次性的项目级事件（开始、完成、中断）。
if rg -q 'statusMessage = String\(localized: "正在评估第|statusMessage = String\(localized: "AI评分已评估|statusMessage = String\(localized: "正在重新评估第 \\\(rangeLabel\)|statusMessage = String\(localized: "离线 AI评分：已评估' \
  "$view_model"; then
  fail "逐张评分进度又被写回顶部项目状态行"
fi
# 发送边界只在隐私页写一次。
# 这条断言原本要求帮助页也出现一遍——两页各写一份，就是重复的来源，而且
# 它们已经漂移过：帮助页写"模型、张数和照片类型"，隐私页写"供应商、模型、
# 预览尺寸和照片数量"，弹窗实际只有前者。发送什么数据属于数据披露，
# 归隐私页；帮助页只讲怎么跑、跑多久、花多少钱。
rg -q '每次请求只发送 1 张' "$privacy" ||
  fail "隐私说明仍未按每次请求照片数表达"
if rg -q '每次请求只发送|张同类型照片' Sources/PhotoCurator/SupportInformationView.swift; then
  fail "帮助页又开始复述发送边界，它只应出现在隐私页"
fi

# 更一般的规则：两页各答一个问题。隐私页答"我的数据去了哪里"，帮助页答
# "怎么用、多少钱、坏了怎么办"。同一个事实只写在能回答它所属问题的那一页——
# 两页各写一份迟早漂移成互相矛盾的说法，这已经发生过一次：帮助页写"模型、
# 张数和照片类型"，隐私页写"供应商、模型、预览尺寸和照片数量"，而确认弹窗
# 实际只有前者。
# 例外：诊断信息讲的是剪贴板产物，必须和"复制诊断信息"按钮同屏，故不设限。
support_view="Sources/PhotoCurator/SupportInformationView.swift"
for data_claim in 原图 原照片 只读 EXIF Keychain 匿名 不发送; do
  if rg -q "$data_claim" "$support_view"; then
    fail "帮助页出现数据流向承诺「$data_claim」，这类事实只属于「隐私与数据」"
  fi
done

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
