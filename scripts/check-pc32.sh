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

rg -q 'String\(localized: "打开任意一张照片"\)' "$onboarding" ||
  fail "第一步没有允许打开任意照片"
rg -q 'String\(localized: "双击任意人物照片，或选中后点击“预览”。"\)' "$onboarding" ||
  fail "打开人物照片的操作说明仍不明确"
if rg -q '左上角第一张|打开的第一张照片' \
  Sources/PhotoCurator "$catalog"; then
  fail "用户界面仍绑定固定照片"
fi

rg -q 'demoGuidedKeeperPhotoID = selectedPhotoID' "$view_model" ||
  fail "打开大图后没有记录实际教学照片"
rg -q 'demoGuidedKeeperPhotoID = photoID' "$view_model" ||
  fail "人工保留后没有锁定实际教学照片"
rg -q 'demoFinalSelectionPhotoIDs' "$view_model" ||
  fail "离线评分没有尊重人工保留项"

rg -q 'let secondPhotoID = viewModel\.photos\[1\]\.id' "$tests" ||
  fail "缺少打开第二张照片的回归测试"
rg -q 'XCTAssertTrue\(viewModel\.aiFinalSelectionPhotoIDs\.contains\(secondPhotoID\)\)' "$tests" ||
  fail "缺少人工保留项进入最终结果的断言"
rg -q 'XCTAssertEqual\(viewModel\.pendingAIFinalSelectionAcceptanceCount, 3\)' "$tests" ||
  fail "缺少最终数量仍收敛到 4 张的断言"

printf 'PC-32 检查通过：任意照片可推进教学，人工保留项与最终数量一致。\n'
