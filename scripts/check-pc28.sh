#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-28 检查失败：%s\n' "$1" >&2
  exit 1
}

contract="Sources/PhotoCurator/AestheticReviewContract.swift"
content="Sources/PhotoCurator/ContentView.swift"
preview="Sources/PhotoCurator/PhotoPreviewView.swift"
filter="Sources/PhotoCurator/PhotoGridFilter.swift"
demo="Sources/PhotoCurator/DemoModeLibrary.swift"
schema="docs/ai/REVIEW_SCHEMA.json"

for field in \
  moment \
  composition \
  subject \
  lighting \
  storytelling; do
  rg -q "let $field: Int" "$contract" ||
    fail "统一契约缺少维度：$field"
done
rg -q 'let dimensions: AestheticScoreDimensions' "$contract" ||
  fail "评分记录缺少五维对象"
rg -q 'let summary: String' "$contract" ||
  fail "评分记录缺少 AI 总结"
rg -q 'case invalidDimensions' "$contract" ||
  fail "Validator 未校验维度"
rg -q 'case invalidSummary' "$contract" ||
  fail "Validator 未校验总结"
rg -q '\(4\.\.\.120\)\.contains\(trimmed\.count\)' "$contract" ||
  fail "总结长度边界不是 4–120"

jq -e '
  (
    .properties.reviews.items.required
    | contains([
        "photo_id",
        "dimensions",
        "reasons",
        "summary"
      ])
  )
  and (.properties.reviews.items.properties.rank == null)
  and (.properties.reviews.items.properties.score == null)
  and (.properties.reviews.items.required | index("score") == null)
  and
  (
    .properties.reviews.items.properties.dimensions.required
    | contains([
        "moment",
        "composition",
        "subject",
        "lighting",
        "storytelling"
      ])
  )
' "$schema" >/dev/null ||
  fail "文档 JSON Schema 未完整声明评分详情"

rg -q 'let dimensions = Dimensions' \
  Sources/PhotoCurator/ArkAestheticReviewClient.swift ||
  fail "方舟工具 schema 缺少 dimensions"
rg -q 'let dimensions: DimensionsProperty' \
  Sources/PhotoCurator/MiniMaxAestheticReviewClient.swift ||
  fail "MiniMax 工具 schema 缺少 dimensions"
rg -q '"dimensions": scoreDimensionsSchema' \
  Sources/PhotoCurator/AnthropicAestheticReviewClient.swift ||
  fail "Anthropic 工具 schema 缺少 dimensions"
rg -q '"dimensions":\{"moment":92' \
  Sources/PhotoCurator/ArkAestheticReviewClient.swift ||
  fail "OpenAI-compatible 共用 Prompt 缺少五维 JSON"
for client in \
  ArkAestheticReviewClient.swift \
  MiniMaxAestheticReviewClient.swift \
  OpenAICompatibleAestheticReviewClient.swift \
  AnthropicAestheticReviewClient.swift; do
  rg -q 'AestheticReviewPrompt.maximumOutputTokens' \
    "Sources/PhotoCurator/$client" ||
    fail "$client 未使用评分详情输出上限"
done

rg -q 'case aiScored' "$filter" ||
  fail "筛选器缺少已AI评分"
rg -q 'case \.aiScored: String\(localized: "已AI评分"\)' "$filter" ||
  fail "已评分筛选名称错误"
if rg -q 'aiSelected' "$filter"; then
  fail "评分优先筛选应已移除"
fi
rg -q 'case \.aiScored: String\(localized: "已AI评分"\)' "$filter" ||
  fail "最终胜出筛选名称错误"
rg -q 'photos\.filter \{ !\$0\.aestheticRecommendations\.isEmpty \}' "$filter" ||
  fail "已AI评分没有覆盖所有有效评分照片"
rg -q 'primaryAestheticRecommendation' \
  Sources/PhotoCurator/PhotoItem.swift "$content" ||
  fail "卡片没有按最终批次优先选择总分"
rg -Fq 'String(localized: "AI \(recommendation.total(with: weights)) 分")' "$content" ||
  fail "评分卡片没有显示总分"
rg -q 'String\(localized: "查看评分"\)' "$content" ||
  fail "选中评分照片后缺少查看评分入口"

for text in \
  AI评分详情 \
  总分 \
  具体评价 \
  AI总结; do
  rg -q "$text" "$preview" ||
    fail "大图评分详情缺少：$text"
done
rg -q 'ForEach\(AestheticScoreDimension\.allCases\)' "$preview" ||
  fail "大图没有渲染五维评分"
rg -q 'photo-preview\.score-detail' "$preview" ||
  fail "评分详情缺少稳定无障碍标识"
rg -q 'PhotoPreviewNavigator\.photoID' "$preview" ||
  fail "评分详情没有复用当前筛选连续导航"

rg -q 'dimensions: AestheticScoreDimensions' "$demo" ||
  fail "离线样例缺少五维评分"
rg -q 'summary: score >= 85' "$demo" ||
  fail "离线样例缺少 AI 总结"
rg -q 'subtracting\(scoredPhotoIDs\)' \
  Sources/PhotoCurator/PhotoLibraryViewModel.swift ||
  fail "已评分照片仍会显示为待AI评分"
if rg -n 'aestheticRecommendations' \
  Sources/PhotoCurator/ProjectPersistence.swift; then
  fail "评分详情不得进入项目持久化"
fi

rg -q 'testRejectsInvalidDimensionOrSummary' \
  Tests/PhotoCuratorTests/AestheticReviewContractTests.swift ||
  fail "缺少维度与总结校验测试"
rg -q 'testPreservesManualAndFinalIndependentScoresForSamePhoto' \
  Tests/PhotoCuratorTests/AestheticReviewContractTests.swift ||
  fail "缺少多阶段评分保留测试"
rg -q 'testAIScoredFilterShowsEveryPhotoWithAValidatedScore' \
  Tests/PhotoCuratorTests/PhotoGridFilterTests.swift ||
  fail "缺少已评分筛选测试"
rg -q 'testPrimaryScorePrefersFinalSelectionRecord' \
  Tests/PhotoCuratorTests/PhotoGridFilterTests.swift ||
  fail "缺少卡片主评分优先级测试"

for screenshot in \
  docs/interaction-screenshots/ai-scored-grid-zh-Hans-920x640.png \
  docs/interaction-screenshots/ai-scored-grid-en-920x640.png \
  docs/interaction-screenshots/photo-score-details-zh-Hans.png \
  docs/interaction-screenshots/photo-score-details-en.png; do
  [[ -s "$screenshot" ]] ||
    fail "缺少视觉验收快照：$screenshot"
done

for document in \
  AGENTS.md \
  docs/ai/SCORING.md \
  docs/engineering/DATA_CONTRACTS.md \
  docs/product/OVERVIEW.md \
  docs/privacy/APP_REVIEW_DEMO.md \
  docs/engineering/TASKS.md; do
  rg -q '五维|dimensions|five dimensions' "$document" ||
    fail "$document 未记录五维评分"
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

rg -q '## PC-28 可解释 AI评分详情' docs/engineering/TASKS.md ||
  fail "任务卡缺少 PC-28"
rg -A2 '## PC-28 可解释 AI评分详情' docs/engineering/TASKS.md |
  rg -q '\*\*状态：已完成\*\*' ||
  fail "PC-28 尚未标记完成"

printf 'PC-28 检查通过：评分契约、协议、筛选、详情、样例、双语和视觉验收一致。\n'
