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
# 429 的费用边界从"一律不重试"改成了"有上限地自动退避重试，并在发送确认里披露额外费用"。
# 断言随之改为守住新的边界：重试次数有明确上限、遵守 Retry-After，且确认文案披露额外请求与费用。
rg -q 'HTTP 429、5xx 与网络中断按指数退避自动重试，最多 4 次' docs/ai/PROVIDERS.md ||
  fail "供应商文档没有记录 429 的重试上限"
rg -q 'Retry-After' docs/ai/PROVIDERS.md ||
  fail "供应商文档没有记录 Retry-After 优先"
rg -q 'maximumAutomaticRetryCount = 4' Sources/PhotoCurator/AIFinalSelectionRun.swift ||
  fail "重试上限与文档不一致"
rg -q '自动退避重试，每张最多 4 次并产生额外请求与费用' Sources/PhotoCurator/SupportInformationView.swift ||
  fail "发送确认没有披露自动重试的额外请求与费用"
rg -q '## PC-24 MiniMax-M3 429 诊断' docs/engineering/TASKS.md ||
  fail "任务卡缺少 PC-24"

printf 'PC-24 检查通过：MiniMax Token Plan 429 分类、提示、费用边界和回归测试一致。\n'
