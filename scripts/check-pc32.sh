#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-32 检查失败：%s\n' "$1" >&2
  exit 1
}

onboarding="Sources/PhotoCurator/OnboardingView.swift"
view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
tests="Tests/PhotoCuratorTests/DemoModeLibraryTests.swift"
catalog="Resources/Localizable.xcstrings"

if rg -q '左上角第一张|打开的第一张照片' \
  Sources/PhotoCurator "$catalog"; then
  fail "用户界面仍绑定固定照片"
fi

# 教学不再强制"先保留一张"，但用户随时可以自己保留：离线结果必须和真实评分
# 一样尊重人工决定（真实评分靠 lockedKeeperPhotoIDs）。这条不变量来自旧的
# demoGuidedKeeperPhotoID，现在改为直接读真实的 decision，不再依赖教学产物。
rg -q 'demoFinalSelectionPhotoIDsByCategory' "$view_model" ||
  fail "离线评分没有尊重人工保留项"
rg -q 'manualKeeperIDs' "$view_model" ||
  fail "离线结果不再按人工保留项收敛"
if rg -q 'demoGuidedKeeperPhotoID' "$view_model"; then
  fail "仍在用教学专属的保留项标记，应直接读真实决定"
fi

rg -q 'testDemoScoringKeepsManualKeeperInRecommendations' "$tests" ||
  fail "缺少人工保留项进入最终结果的回归测试"
rg -q 'XCTAssertEqual\(viewModel\.pendingAIFinalSelectionAcceptanceCount, 4\)' "$tests" ||
  fail "缺少最终数量仍收敛到 4 张的断言"

printf 'PC-32 检查通过：任意照片可推进教学，人工保留项与最终数量一致。\n'
