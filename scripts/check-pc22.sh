#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-22 检查失败：%s\n' "$1" >&2
  exit 1
}

project_file="PhotoCurator.xcodeproj/project.pbxproj"
content_view="Sources/PhotoCurator/ContentView.swift"
preview_view="Sources/PhotoCurator/PhotoPreviewView.swift"

rg -q 'PhotoPreviewView\.swift in Sources' "$project_file" ||
  fail "PhotoPreviewView 未加入 Xcode Sources"
rg -q 'accessibilityIdentifier\("sidebar\.ai-settings"\)' "$content_view" ||
  fail "缺少无项目可访问的全局 AI 设置入口"
if rg -q 'accessibilityIdentifier\("ai\.settings"\)' "$content_view"; then
  fail "活动项目区仍保留重复 AI 设置入口"
fi

rg -q 'library\.prepareAIFinalSelectionRun\(\)' "$content_view" ||
  fail "主界面缺少完整 AI评分入口"
if rg -n \
  'AI评分相似照片|prepareAestheticReviewForSelectedPhoto|photo\.review-group' \
  "$content_view" "$preview_view"; then
  fail "界面仍保留局部相似照片评分入口"
fi

rg -q 'TapGesture\(count: 2\)' "$content_view" ||
  fail "照片卡缺少双击大图预览"
rg -q '\.onKeyPress\(\.space\)' "$content_view" ||
  fail "照片卡缺少空格预览"
rg -q 'PhotoPreviewView\(photoIDs:' "$content_view" ||
  fail "主界面未接入大图预览"
rg -q 'maximumPixelSize: 1_600' "$preview_view" ||
  fail "大图预览未请求 1600px 后台解码"
rg -q 'PhotoPreviewNavigator\.photoID' "$preview_view" ||
  fail "大图预览未按当前筛选顺序导航"
for identifier in \
  photo-preview.previous \
  photo-preview.next \
  photo-preview.undecided \
  photo-preview.reject \
  photo-preview.keep; do
  rg -Fq "accessibilityIdentifier(\"$identifier\")" "$preview_view" ||
    fail "大图预览缺少 accessibility identifier: $identifier"
done

rg -q 'var canUndo: Bool' Sources/PhotoCurator/PhotoLibraryViewModel.swift ||
  fail "ViewModel 未暴露真实撤销可用状态"
undo_disable_count="$(
  rg -c '\.disabled\(!library\.canUndo\)' "$content_view"
)"
[[ "$undo_disable_count" -ge 2 ]] ||
  fail "完整与紧凑底栏没有同步禁用撤销"
rg -q '\.disabled\(!library\.canUndo\)' Sources/PhotoCurator/PhotoCuratorApp.swift ||
  fail "选片菜单没有同步禁用撤销"

rg -q 'testMovesWithinCurrentFilteredPhotoOrder' \
  Tests/PhotoCuratorTests/PhotoPreviewNavigatorTests.swift ||
  fail "缺少当前筛选顺序预览导航测试"
rg -q 'XCTAssertTrue\(viewModel\.canUndo\)' \
  Tests/PhotoCuratorTests/DemoModeLibraryTests.swift ||
  fail "缺少撤销可用状态回归测试"

for document in AGENTS.md docs/INTERACTION_AUDIT.md docs/PRODUCT.md docs/TASKS.md; do
  rg -q '大图|预览' "$document" ||
    fail "$document 尚未记录大图预览交互"
done

if rg -n 'URLSession|AIProviderKeyStore|SecItem|https?://' "$preview_view"; then
  fail "本地大图预览不得访问网络或 Keychain"
fi

printf 'PC-22 检查通过：全局设置、完整 AI评分、大图预览、连续导航和撤销状态均已接线。\n'
