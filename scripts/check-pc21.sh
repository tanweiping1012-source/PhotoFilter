#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-21 检查失败：%s\n' "$1" >&2
  exit 1
}

project_file="PhotoCurator.xcodeproj/project.pbxproj"
catalog="Resources/Localizable.xcstrings"

for source in \
  AIModelCatalog.swift \
  AIProviderKeyStore.swift \
  AISettingsView.swift \
  MiniMaxAestheticReviewClient.swift; do
  rg -q "$source in Sources" "$project_file" ||
    fail "$source 未加入 Xcode Sources"
done

rg -q 'case doubaoSeed20Lite' Sources/PhotoCurator/AIModelCatalog.swift ||
  fail "模型目录缺少 Doubao-Seed-2.0 Lite"
rg -q 'case miniMaxM3' Sources/PhotoCurator/AIModelCatalog.swift ||
  fail "模型目录缺少 MiniMax-M3"
rg -q 'apiModelID: "MiniMax-M3"' Sources/PhotoCurator/AIModelCatalog.swift ||
  fail "MiniMax-M3 API model ID 不正确"
rg -q 'supportsImageInput: true' Sources/PhotoCurator/AIModelCatalog.swift ||
  fail "模型目录没有声明图片能力"

rg -q 'selected-ai-model-v1' Sources/PhotoCurator/AIModelCatalog.swift ||
  fail "模型选择没有稳定的非敏感偏好键"
rg -q 'ark-api-key' Sources/PhotoCurator/AIProviderKeyStore.swift ||
  fail "现有方舟 Keychain service 未保留"
rg -q 'ai-api-key\.minimax' Sources/PhotoCurator/AIProviderKeyStore.swift ||
  fail "MiniMax Keychain service 未隔离"

rg -q 'data:image/jpeg;base64' Sources/PhotoCurator/MiniMaxAestheticReviewClient.swift ||
  fail "MiniMax 请求未使用内存 JPEG data URL"
rg -q 'thinking: MiniMaxThinking\(type: "disabled"\)' \
  Sources/PhotoCurator/MiniMaxAestheticReviewClient.swift ||
  fail "MiniMax-M3 未关闭思考"
rg -q 'AestheticReviewValidator\.validate' \
  Sources/PhotoCurator/MiniMaxAestheticReviewClient.swift ||
  fail "MiniMax 响应未经过正式 Validator"
rg -q 'AestheticReviewClient\(' Sources/PhotoCurator/PhotoLibraryViewModel.swift ||
  fail "ViewModel 未通过统一客户端按模型分发"
rg -q 'let model: AIModelDescriptor' Sources/PhotoCurator/PhotoLibraryViewModel.swift ||
  fail "AI 运行上下文未锁定完整模型配置"

rg -q 'AISettingsView' Sources/PhotoCurator/ContentView.swift ||
  fail "主界面未接入多模型设置"
rg -q 'ai-settings\.model' Sources/PhotoCurator/AISettingsView.swift ||
  fail "模型 Picker 缺少稳定 accessibility identifier"
rg -q 'isConfigurationLocked' Sources/PhotoCurator/AISettingsView.swift ||
  fail "运行期间未锁定模型切换"

rg -q 'testRequestUsesMiniMaxM3AndOnlyAnonymousDataURLs' \
  Tests/PhotoCuratorTests/MiniMaxAestheticReviewClientTests.swift ||
  fail "缺少 MiniMax 匿名图片请求测试"
rg -q 'testProviderKeychainServicesAreIsolatedAndArkNameIsStable' \
  Tests/PhotoCuratorTests/AIModelCatalogTests.swift ||
  fail "缺少供应商 Keychain 隔离测试"
rg -q 'testDemoLaunchSkipsKeychainAndPersistence' \
  Tests/PhotoCuratorTests/DemoModeLibraryTests.swift ||
  fail "缺少 Demo 零 Keychain 回归测试"

for document in \
  AGENTS.md \
  docs/ai/PROVIDERS.md \
  docs/engineering/DATA_CONTRACTS.md \
  docs/privacy/PRIVACY_POLICY.md \
  docs/privacy/APP_STORE_PRIVACY.md; do
  rg -q 'MiniMax' "$document" ||
    fail "$document 尚未披露 MiniMax"
done

key_count="$(jq '.strings | length' "$catalog")"
english_count="$(
  jq '[.strings[] | select(.localizations.en.stringUnit.value != null)] | length' \
    "$catalog"
)"
[[ "$key_count" == "$english_count" ]] ||
  fail "String Catalog 有 $((key_count - english_count)) 个键缺少英文"

if rg -n 'isArkAPIKeyConfigured|latestArkUsageMessage|ArkSettingsView' \
  Sources/PhotoCurator; then
  fail "界面或状态机仍残留方舟专用配置命名"
fi

printf 'PC-21 检查通过：模型目录、MiniMax-M3、Keychain 隔离、模型锁定、隐私与测试入口一致。\n'
