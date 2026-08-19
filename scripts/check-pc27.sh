#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-27 检查失败：%s\n' "$1" >&2
  exit 1
}

catalog_source="Sources/PhotoCurator/AIModelCatalog.swift"
key_store="Sources/PhotoCurator/AIProviderKeyStore.swift"
settings="Sources/PhotoCurator/AISettingsView.swift"
project="PhotoCurator.xcodeproj/project.pbxproj"

for source in \
  OpenAICompatibleAestheticReviewClient.swift \
  AnthropicAestheticReviewClient.swift; do
  rg -q "$source in Sources" "$project" ||
    fail "$source 未加入 Xcode Sources"
done

for model_case in \
  openAIGPT54Mini \
  anthropicClaudeSonnet5 \
  googleGemini37Flash \
  alibabaQwen38Max \
  xAIGrok46 \
  customOpenAICompatible; do
  rg -q "case $model_case" "$catalog_source" ||
    fail "模型目录缺少 $model_case"
done

for api_model in \
  gpt-5.4-mini \
  claude-sonnet-5 \
  gemini-3.7-flash \
  qwen3.8-max \
  grok-4.6; do
  rg -q "$api_model" "$catalog_source" ||
    fail "模型目录缺少 API model ID: $api_model"
done

for domain in \
  api.openai.com \
  api.anthropic.com \
  generativelanguage.googleapis.com \
  dashscope.aliyuncs.com \
  api.x.ai; do
  rg -q "$domain" "$catalog_source" ||
    fail "模型目录缺少端点：$domain"
  rg -q "$domain" docs/PRIVACY_POLICY.md ||
    fail "隐私政策缺少端点：$domain"
done

rg -q 'case openAICompatibleChatCompletions' "$catalog_source" ||
  fail "缺少 OpenAI-compatible 协议"
rg -q 'case anthropicMessages' "$catalog_source" ||
  fail "缺少 Anthropic Messages 协议"
rg -q 'OpenAICompatibleAestheticReviewClient' \
  Sources/PhotoCurator/MiniMaxAestheticReviewClient.swift ||
  fail "统一客户端没有路由 OpenAI-compatible"
rg -q 'AnthropicAestheticReviewClient' \
  Sources/PhotoCurator/MiniMaxAestheticReviewClient.swift ||
  fail "统一客户端没有路由 Anthropic Messages"
rg -q 'pendingAIFinalSelectionModelSnapshot = selectedAIModel' \
  Sources/PhotoCurator/PhotoLibraryViewModel.swift ||
  fail "完整 AI评分运行没有锁定自定义 endpoint 与 model ID"

for service in \
  ai-api-key.openai \
  ai-api-key.anthropic \
  ai-api-key.google-gemini \
  ai-api-key.alibaba-model-studio \
  ai-api-key.xai \
  ai-api-key.custom-openai-compatible; do
  rg -q "$service" "$key_store" ||
    fail "Keychain service 未隔离：$service"
done

rg -q 'custom-openai-compatible-configuration-v1' "$catalog_source" ||
  fail "自定义兼容配置缺少稳定偏好键"
rg -q 'scheme == "https"' "$catalog_source" ||
  fail "自定义 endpoint 没有要求 HTTPS"
rg -q 'scheme == "http" && isLoopback' "$catalog_source" ||
  fail "自定义 endpoint 没有限制远程 HTTPS"
rg -q 'components\.user == nil' "$catalog_source" ||
  fail "自定义 endpoint 没有拒绝 URL 用户信息"
rg -q 'components\.query == nil' "$catalog_source" ||
  fail "自定义 endpoint 没有拒绝 query"
rg -q 'hasSuffix\("/chat/completions"\)' "$catalog_source" ||
  fail "自定义 endpoint 没有限定 Chat Completions"

for identifier in \
  ai-settings.custom-display-name \
  ai-settings.custom-endpoint \
  ai-settings.custom-model-id \
  ai-settings.save-custom-configuration; do
  rg -Fq "\"$identifier\"" "$settings" ||
    fail "自定义设置缺少无障碍标识：$identifier"
done

rg -q 'testOpenAICompatibleBuiltInsShareOneRequestEnvelope' \
  Tests/PhotoCuratorTests/ProtocolAdapterTests.swift ||
  fail "缺少 OpenAI-compatible 共用 envelope 测试"
rg -q 'testAnthropicMessagesUsesBase64ImagesAndForcedTool' \
  Tests/PhotoCuratorTests/ProtocolAdapterTests.swift ||
  fail "缺少 Anthropic 图片与工具测试"
rg -q 'testCustomCompatibleConfigurationValidatesAndRoundTrips' \
  Tests/PhotoCuratorTests/AIModelCatalogTests.swift ||
  fail "缺少自定义配置安全与持久化测试"

for document in \
  AGENTS.md \
  docs/AI_MODEL_PROVIDERS.md \
  docs/AI_PROTOCOL_ADAPTERS.md \
  docs/DATA_CONTRACTS.md \
  docs/PRIVACY_POLICY.md \
  docs/APP_STORE_PRIVACY.md \
  docs/TASKS.md; do
  rg -q 'OpenAI' "$document" ||
    fail "$document 尚未记录多协议扩展"
done

catalog="Resources/Localizable.xcstrings"
key_count="$(jq '.strings | length' "$catalog")"
english_count="$(
  jq '[.strings[] | select(.localizations.en.stringUnit.value != null)] | length' \
    "$catalog"
)"
[[ "$key_count" == "$english_count" ]] ||
  fail "String Catalog 有 $((key_count - english_count)) 个键缺少英文"

printf 'PC-27 检查通过：主流模型、协议复用、自定义接口、Key 隔离和隐私披露一致。\n'
