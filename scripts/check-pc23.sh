#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-23 检查失败：%s\n' "$1" >&2
  exit 1
}

catalog="Resources/Localizable.xcstrings"
model_source="Sources/PhotoCurator/AIModelCatalog.swift"
view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
settings_view="Sources/PhotoCurator/AISettingsView.swift"
minimax_client="Sources/PhotoCurator/MiniMaxAestheticReviewClient.swift"

for size_case in small medium large; do
  rg -q "case $size_case" "$model_source" ||
    fail "缺少 AI 预览档位：$size_case"
done
for pixels in 512 '1_024' '1_536'; do
  rg -q "$pixels" "$model_source" ||
    fail "缺少 AI 预览像素边界：$pixels"
done
for detail in low default high; do
  rg -q "\"$detail\"" "$model_source" ||
    fail "缺少 MiniMax detail 映射：$detail"
done
rg -q 'selected-ai-preview-size-v1' "$model_source" ||
  fail "AI 预览尺寸没有稳定的全局偏好键"
rg -q 'return \.small' "$model_source" ||
  fail "旧版本升级必须默认保持小尺寸"

rg -q 'ai-settings\.preview-size' "$settings_view" ||
  fail "尺寸 Picker 缺少稳定 accessibility identifier"
rg -q '\.pickerStyle\(\.segmented\)' "$settings_view" ||
  fail "小/中/大必须使用分段控件"
rg -q 'selectedPreviewSize\.guidance' "$settings_view" ||
  fail "设置页没有解释当前档位取舍"
rg -q '上传量、等待时间和供应商费用' "$settings_view" ||
  fail "设置页没有披露大图成本"

pending_lock_count="$(rg -c 'let previewSize: AIReviewPreviewSize' "$view_model")"
[[ "$pending_lock_count" -ge 1 ]] ||
  fail "完整 AI评分任务没有锁定预览尺寸"
rg -q 'pendingAIFinalSelectionPreviewSizeSnapshot = selectedAIPreviewSize' "$view_model" ||
  fail "完整 AI评分准备时没有复制当前尺寸"
rg -q 'let maximumPixelSize = previewSize\.maximumPixelSize' "$view_model" ||
  fail "JPEG 编码没有使用锁定尺寸"
rg -q 'Task\.detached\(priority: \.userInitiated\)' "$view_model" ||
  fail "大尺寸 JPEG 编码仍可能阻塞主线程"

rg -q 'case maximumPixelSize = "max_long_side_pixel"' "$minimax_client" ||
  fail "MiniMax 请求缺少 max_long_side_pixel"
rg -q 'try image\.encode\(detail, forKey: \.detail\)' "$minimax_client" ||
  fail "MiniMax 请求没有映射 detail"
rg -q 'previewSize: context\.previewSize' "$view_model" ||
  fail "完整 AI评分请求没有使用锁定尺寸"

# 尺寸不再挤进发送确认，而是常驻在侧栏 AI评分区（运行期间设置被锁定，展示值即锁定值）。
rg -q 'library\.selectedAIPreviewSize\.displayName' Sources/PhotoCurator/ContentView.swift ||
  fail "侧栏没有常驻展示当前 AI 预览尺寸"
rg -q 'isConfigurationLocked' Sources/PhotoCurator/AISettingsView.swift ||
  fail "运行期间没有锁定 AI 配置"

rg -q 'testEachPreviewSizeProducesItsExactLongestEdge' \
  Tests/PhotoCuratorTests/AIReviewPreviewEncoderTests.swift ||
  fail "缺少三档实际像素测试"
rg -q 'testEncodedPreviewDoesNotCopyGPSMetadata' \
  Tests/PhotoCuratorTests/AIReviewPreviewEncoderTests.swift ||
  fail "缺少高分辨率预览去 GPS 测试"
rg -q 'testLargePreviewUsesHighDetailAnd1536PixelBoundary' \
  Tests/PhotoCuratorTests/MiniMaxAestheticReviewClientTests.swift ||
  fail "缺少 MiniMax 大尺寸参数测试"
rg -q 'testPreviewSizeStoreDefaultsToSmallAndRoundTrips' \
  Tests/PhotoCuratorTests/AIModelCatalogTests.swift ||
  fail "缺少尺寸偏好默认与持久化测试"

for document in \
  AGENTS.md \
  README.md \
  docs/ai/PREVIEW_SIZE.md \
  docs/engineering/DATA_CONTRACTS.md \
  docs/privacy/PRIVACY_POLICY.md \
  docs/privacy/APP_STORE_PRIVACY.md \
  docs/engineering/TASKS.md; do
  rg -q '1536px' "$document" ||
    fail "$document 尚未披露最大 AI 预览尺寸"
done

rg -q '1536px' Sources/PhotoCurator/PrivacyInformationView.swift ||
  fail "App 内隐私说明尚未披露最大 AI 预览尺寸"
rg -q '512/1024/1536px' scripts/package-dmg.sh ||
  fail "DMG 安装说明尚未披露可选 AI 预览尺寸"

key_count="$(jq '.strings | length' "$catalog")"
english_count="$(
  jq '[.strings[] | select(.localizations.en.stringUnit.value != null)] | length' \
    "$catalog"
)"
[[ "$key_count" == "$english_count" ]] ||
  fail "String Catalog 有 $((key_count - english_count)) 个键缺少英文"

printf 'PC-23 检查通过：三档尺寸、任务锁定、后台编码、MiniMax 参数、隐私和测试一致。\n'
