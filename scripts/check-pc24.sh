#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-24 检查失败：%s\n' "$1" >&2
  exit 1
}

client="Sources/PhotoCurator/MiniMaxAestheticReviewClient.swift"
errors="Sources/PhotoCurator/ArkAestheticReviewClient.swift"
tests="Tests/PhotoCuratorTests/MiniMaxAestheticReviewClientTests.swift"

rg -q 'MiniMax-TokenPlan-RateLimit' "$client" ||
  fail "Token Plan 429 没有安全分类"
rg -q 'apiKey\.hasPrefix\("sk-cp"\)' "$client" ||
  fail "MiniMax Key 类型没有按官方 Token Plan 前缀区分"
rg -q 'statusCode == 429' "$client" ||
  fail "MiniMax HTTP 429 没有进入限流分类"
rg -q '5 小时额度、周额度或动态限流' "$errors" ||
  fail "Token Plan 429 没有可执行的额度提示"
rg -q 'testObservedRateLimitShapeClassifiesTokenPlanFailure' "$tests" ||
  fail "缺少 MiniMax 实际 429 响应形状回归测试"
rg -q 'testOrdinaryKeyUsesGenericMiniMaxRateLimitCategory' "$tests" ||
  fail "缺少普通 API Key 的 429 分类测试"
rg -q 'HTTP 429 不自动重试' docs/AI_MODEL_PROVIDERS.md ||
  fail "供应商文档没有保留 429 费用边界"
rg -q '## PC-24 MiniMax-M3 429 诊断' docs/TASKS.md ||
  fail "任务卡缺少 PC-24"

printf 'PC-24 检查通过：MiniMax Token Plan 429 分类、提示、费用边界和回归测试一致。\n'
