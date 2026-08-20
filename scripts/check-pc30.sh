#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-30 检查失败：%s\n' "$1" >&2
  exit 1
}

view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
similarity="Sources/PhotoCurator/SimilarityGrouper.swift"
families="Sources/PhotoCurator/CandidateFamilyIndex.swift"
ranker="Sources/PhotoCurator/LocalCandidateRanker.swift"

if rg -q 'BurstGrouper\.assigningGroups' "$view_model"; then
  fail "分析流程仍使用纯时间分组"
fi
rg -q 'updated\.burstGroup = nil' "$view_model" ||
  fail "新分析没有清空旧时间分组"
rg -q 'SimilarityGrouper\.assigningGroups' "$view_model" ||
  fail "分析流程缺少画面相似识别"

rg -q 'isStrictNearDuplicate' "$similarity" ||
  fail "相似算法缺少严格视觉匹配"
rg -q 'isTemporallyCloseScene' "$similarity" ||
  fail "相似算法缺少时间辅助的边界匹配"
rg -q 'isStrictNearDuplicate \|\| isTemporallyCloseScene' "$similarity" ||
  fail "时间没有被限制为视觉匹配的辅助条件"

if rg -q 'burstGroup' "$families"; then
  fail "候选家族仍读取纯时间标记"
fi
if rg -q 'kind: \.burst|photo\.burstGroup' "$ranker"; then
  fail "本地排序仍生成纯时间推荐"
fi

rg -q 'testSameCaptureTimeCannotGroupVisuallyUnrelatedPhotos' \
  Tests/PhotoCuratorTests/SimilarityGrouperTests.swift ||
  fail "缺少同时间不同画面反例测试"
rg -q 'testLegacyTimeGroupCannotBridgeVisualSimilarityFamilies' \
  Tests/PhotoCuratorTests/CandidateFamilyIndexTests.swift ||
  fail "缺少旧时间标记家族隔离测试"
rg -q 'testIgnoresLegacyTimeOnlyGroup' \
  Tests/PhotoCuratorTests/LocalCandidateRankerTests.swift ||
  fail "缺少旧时间标记排序隔离测试"

for source in \
  Sources/PhotoCurator/ContentView.swift \
  Sources/PhotoCurator/PhotoPreviewView.swift \
  Sources/PhotoCurator/PhotoLibraryViewModel.swift \
  Sources/PhotoCurator/OnboardingView.swift \
  Resources/Localizable.xcstrings; do
  if rg -n \
    '连拍组|相似组|候选组|AI评分此组|相似或连拍|本地优先|候补|本地建议' \
    "$source"; then
    fail "$source 仍包含不应向用户展示的内部概念"
  fi
done

if rg -n \
  'AI评分相似照片|AestheticReviewGroupPlanner|AestheticReviewRunPlanner' \
  Sources Tests Resources/Localizable.xcstrings; then
  fail "局部相似照片评分入口或旧规划器仍然存在"
fi
rg -q 'library\.prepareAIFinalSelectionRun\(' \
  Sources/PhotoCurator/ContentView.swift ||
  fail "主界面缺少统一的完整 AI评分入口"
rg -q 'inspectorSection\("相似照片"\)' \
  Sources/PhotoCurator/PhotoPreviewView.swift ||
  fail "大图详情没有统一为相似照片"

for document in \
  AGENTS.md \
  docs/product/SIMILAR_PHOTOS.md \
  docs/product/OVERVIEW.md \
  docs/engineering/DATA_CONTRACTS.md \
  docs/engineering/HARNESS.md \
  docs/privacy/APP_STORE_PRIVACY.md \
  docs/engineering/TASKS.md; do
  rg -q '画面相似|视觉相似' "$document" ||
    fail "$document 未记录视觉优先策略"
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

[[ -s docs/interaction-screenshots/similar-photos-unified-zh-Hans.png ]] ||
  fail "缺少统一相似照片界面快照"

rg -A2 '## PC-30 视觉优先的相似照片策略' docs/engineering/TASKS.md |
  rg -q '\*\*状态：已完成\*\*' ||
  fail "PC-30 尚未标记完成"

printf 'PC-30 检查通过：画面相似为主、时间仅辅助，用户界面只保留相似照片概念。\n'
