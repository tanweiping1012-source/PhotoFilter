#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-33 检查失败：%s\n' "$1" >&2
  exit 1
}

contract="Sources/PhotoCurator/AestheticReviewContract.swift"
prompt="Sources/PhotoCurator/ArkAestheticReviewClient.swift"
run="Sources/PhotoCurator/AIFinalSelectionRun.swift"
view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
preview="Sources/PhotoCurator/PhotoPreviewView.swift"
content="Sources/PhotoCurator/ContentView.swift"
schema="docs/ai/REVIEW_SCHEMA.json"
tests="Tests/PhotoCuratorTests/AIFinalSelectionRunTests.swift"

rg -q 'static let version = "v3"' "$contract" ||
  fail "独立评分契约没有保留在当前 v3"
if rg -q 'let rank: Int|case rank|invalidRanks' "$contract"; then
  fail "统一评分契约仍包含请求内名次"
fi
jq -e '
  .properties.version.const == "v3"
  and (.properties.reviews.items.properties.rank == null)
  and (.properties.reviews.items.required | index("rank") == null)
' "$schema" >/dev/null ||
  fail "文档 JSON Schema 仍要求 rank"

for client in \
  ArkAestheticReviewClient.swift \
  MiniMaxAestheticReviewClient.swift \
  AnthropicAestheticReviewClient.swift; do
  if rg -q '"rank",|let rank: Integer|case rank' \
    "Sources/PhotoCurator/$client"; then
    fail "$client 的工具 schema 仍要求请求内名次"
  fi
done

rg -q '一次附带多张图片只为传输效率，不代表候选组' "$prompt" ||
  fail "Prompt 没有说明多图只是传输窗口"
rg -q '不得比较图片，不得返回名次' "$prompt" ||
  fail "Prompt 没有禁止组内比较和名次"
rg -q '90–100.*80–89.*70–79.*60–69.*0–59' "$prompt" ||
  fail "Prompt 缺少跨请求统一评分标尺"
rg -q 'case relativeComparison' "$contract" ||
  fail "Validator 没有拦截模型返回的相对评价"

rg -q 'struct AIFinalSelectionScore' "$run" ||
  fail "最终运行没有累计每张照片的独立分数"
rg -q 'rankedCandidatePhotoIDs' "$run" "$view_model" ||
  fail "完整评分后没有执行全局排序"
rg -q 'var scoredCandidates: \[AIFinalSelectionScore\]' "$view_model" ||
  fail "运行上下文仍未保存全部候选分数"
if rg -q 'winnerPhotoIDs|winnerLocalPhotoID' "$run" "$view_model"; then
  fail "最终运行仍使用请求内胜者晋级"
fi

rg -q '第.*名' "$preview" ||
  fail "评分详情没有展示分类名次"
rg -q '独立评分' "$preview" ||
  fail "手动评分仍被表达为组内排名"
rg -q '只在人物或风景内按统一分数排序' Sources/PhotoCurator/SupportInformationView.swift ||
  fail "发送确认没有说明分类内全局排序"

rg -q 'testGlobalRankingIgnoresTransferWindowBoundaries' "$tests" ||
  fail "缺少跨请求窗口全局排序测试"
rg -q 'testGlobalRankingRequiresEveryCandidateScore' "$tests" ||
  fail "缺少不完整评分禁止生成结果测试"
rg -q 'testRejectsRelativeComparisonCommentary' \
  Tests/PhotoCuratorTests/AestheticReviewContractTests.swift ||
  fail "缺少相对评价拦截测试"
rg -q 'testTransferWindowsAvoidSinglePhotoTail' "$tests" ||
  fail "缺少 2–5 张传输窗口测试"

for document in \
  docs/ai/SCORING.md \
  docs/engineering/DATA_CONTRACTS.md \
  docs/product/OVERVIEW.md \
  docs/engineering/HARNESS.md \
  docs/engineering/TASKS.md; do
  rg -q '独立评分|独立评估' "$document" ||
    fail "$document 未记录独立评分"
  rg -q '全局排序|全局名次' "$document" ||
    fail "$document 未记录全局排序"
done

printf 'PC-33 检查通过：模型独立评分，App 汇总当前类型全部候选后执行稳定排序。\n'
