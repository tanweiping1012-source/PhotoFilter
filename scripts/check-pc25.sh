#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-25 检查失败：%s\n' "$1" >&2
  exit 1
}

old_terms='AI (复核|策展|精选|建议|候选|优先|候补)|AI(复核|策展|精选|建议|候选|优先|候补)|精选目标|审美复核|审美评分|审美排序|AI 模型设置|AI 模型与 API Key'

if rg -n "$old_terms" \
  Sources \
  Tests \
  Resources/Localizable.xcstrings \
  scripts/localization-en.json \
  AGENTS.md \
  README.md \
  docs; then
  fail "仍存在未统一的用户术语"
fi

rg -q 'Text\("AI评分"\)' Sources/PhotoCurator/ContentView.swift ||
  fail "侧栏缺少统一的 AI评分标题"
rg -q 'library\.prepareAIFinalSelectionRun\(' \
  Sources/PhotoCurator/ContentView.swift ||
  fail "缺少统一的完整 AI评分入口"
if rg -n 'AI评分相似照片|发送并复核' \
  Sources/PhotoCurator/ContentView.swift \
  Sources/PhotoCurator/PhotoPreviewView.swift \
  Resources/Localizable.xcstrings; then
  fail "仍存在局部评分入口文案"
fi
rg -q 'case \.aiCandidates: String\(localized: "待AI评分"\)' \
  Sources/PhotoCurator/PhotoGridFilter.swift ||
  fail "输入筛选未统一为待AI评分"
rg -q 'case \.aiScored: String\(localized: "已AI评分"\)' \
  Sources/PhotoCurator/PhotoGridFilter.swift ||
  fail "已评分筛选未统一为已AI评分"
# "评分优先"筛选已移除：它不落盘，重启后对该项目永久为空，是纯粹的理解负担。
# 最终结果改由底部"采纳"命令承担，这里断言筛选枚举里不再出现它。
if rg -q 'aiSelected|评分优先' Sources/PhotoCurator/PhotoGridFilter.swift; then
  fail "评分优先筛选应已移除"
fi
rg -Fq '采纳 \(library.pendingAIFinalSelectionAcceptanceCount) 张评分结果' \
  Sources/PhotoCurator/ContentView.swift ||
  fail "最终结果缺少统一的采纳入口"
# 帮助页行标题已改为用户会问的问题（"需要 API Key 吗"），术语一致性由上面的
# old_terms 全仓库扫描承担，这里只断言分区标题仍用统一术语。
rg -q 'Section\("AI评分规则"\)' Sources/PhotoCurator/SupportInformationView.swift ||
  fail "帮助页未统一为 AI评分"
rg -q 'Text\("AI评分设置"\)' Sources/PhotoCurator/AISettingsView.swift ||
  fail "设置页未统一为 AI评分设置"
rg -q 'Text\("保留目标"\)' Sources/PhotoCurator/ContentView.swift ||
  fail "数量目标未统一为保留目标"

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

printf 'PC-25 检查通过：AI评分术语、阶段名称、双语和文档已统一。\n'
