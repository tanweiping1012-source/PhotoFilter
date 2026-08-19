#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-34 检查失败：%s\n' "$1" >&2
  exit 1
}

catalog="Sources/PhotoCurator/AIModelCatalog.swift"
settings="Sources/PhotoCurator/AISettingsView.swift"
key_store="Sources/PhotoCurator/AIProviderKeyStore.swift"
verifier="Sources/PhotoCurator/AIModelConnectionVerifier.swift"
discovery="Sources/PhotoCurator/AIModelDiscoveryService.swift"
project="PhotoCurator.xcodeproj/project.pbxproj"
protocol_tests="Tests/PhotoCuratorTests/ProtocolAdapterTests.swift"
verifier_tests="Tests/PhotoCuratorTests/AIModelConnectionVerifierTests.swift"

for provider in \
  volcengineArk \
  miniMax \
  openAI \
  anthropic \
  googleGemini \
  alibabaModelStudio \
  xAI \
  moonshotKimi \
  zhipuGLM \
  tencentHunyuan \
  customOpenAICompatible; do
  rg -q "case $provider" "$catalog" ||
    fail "品牌目录缺少 $provider"
done

for model in \
  doubaoSeed21Pro \
  doubaoSeed20Lite \
  miniMaxM3 \
  openAIGPT56Sol \
  openAIGPT56Terra \
  openAIGPT56Luna \
  openAIGPT55 \
  openAIGPT54 \
  openAIGPT54Mini \
  openAIGPT54Nano \
  openAIOther \
  anthropicClaudeFable5 \
  anthropicClaudeOpus5 \
  anthropicClaudeOpus48 \
  anthropicClaudeOpus47 \
  anthropicClaudeOpus46 \
  anthropicClaudeOpus45 \
  anthropicClaudeSonnet5 \
  anthropicClaudeSonnet46 \
  anthropicClaudeSonnet45 \
  anthropicClaudeHaiku45 \
  anthropicOther \
  googleGemini31ProPreview \
  googleGemini37Flash \
  googleGemini35FlashLite \
  alibabaQwen38Max \
  alibabaQwen37Plus \
  alibabaQwen37Flash \
  xAIGrok46 \
  moonshotKimiK3 \
  moonshotKimiK26 \
  moonshotKimiK25 \
  zhipuGLM46V \
  zhipuGLM46VFlashX \
  zhipuGLM46VFlash \
  tencentHunyuanVision \
  customOpenAICompatible; do
  rg -q "case $model" "$catalog" ||
    fail "模型目录缺少 $model"
done

rg -q 'func models\(' "$catalog" ||
  fail "模型目录不能按品牌过滤"
rg -q 'func defaultModelID\(' "$catalog" ||
  fail "品牌切换没有推荐默认模型"
rg -q 'supportsJSONResponseFormat' "$catalog" \
  Sources/PhotoCurator/OpenAICompatibleAestheticReviewClient.swift ||
  fail "目录没有声明 JSON mode 能力"

rg -q 'Picker\("品牌"' "$settings" ||
  fail "设置页缺少品牌 Picker"
rg -q 'Picker\("模型"' "$settings" ||
  fail "设置页缺少模型 Picker"
for identifier in \
  ai-settings.provider \
  ai-settings.model \
  ai-settings.additional-model-id \
  ai-settings.discover-models \
  ai-settings.verify-and-save-key \
  ai-settings.verify-saved-key; do
  rg -Fq "\"$identifier\"" "$settings" ||
    fail "设置页缺少无障碍标识：$identifier"
done

for service in \
  ai-api-key.moonshot-kimi \
  ai-api-key.zhipu-glm \
  ai-api-key.tencent-hunyuan; do
  rg -q "$service" "$key_store" ||
    fail "新增品牌 Keychain service 未隔离：$service"
done

rg -q 'AIModelConnectionVerifier.swift in Sources' "$project" ||
  fail "连接验证器未加入 Xcode target"
rg -q 'AIModelDiscoveryService.swift in Sources' "$project" ||
  fail "模型发现服务未加入 Xcode target"
rg -q 'demo-01-coastal-road.jpg' "$verifier" ||
  fail "连接验证没有使用内置测试图"
rg -q 'AestheticReviewClient\(model: model\)\.review' "$verifier" ||
  fail "连接验证没有走正式协议客户端"
rg -q 'AestheticReviewValidator\.validate' "$verifier" ||
  fail "连接验证没有走正式评分契约"
rg -q 'api\.openai\.com/v1/models' "$discovery" ||
  fail "OpenAI 模型列表接口缺失"
rg -q 'api\.anthropic\.com/v1/models' "$discovery" ||
  fail "Anthropic 模型列表接口缺失"
rg -q 'AIProviderKeyStore\.save' "$settings" ||
  fail "验证成功后没有保存 Key"
rg -q 'try await AIModelConnectionVerifier\(\)\.verify' "$settings" ||
  fail "设置页没有执行真实连接验证"
rg -q 'AIModelVerificationStore\.markVerified' "$settings" ||
  fail "连接成功后没有记录当前具体模型"
rg -q 'modelVerificationCheck\(selectedAIModel\)' \
  Sources/PhotoCurator/PhotoLibraryViewModel.swift ||
  fail "未验证的具体模型仍可开始 AI评分"
if rg -q '127\.0\.0\.1:7777|debug-point|minimax-m3-429' \
  Sources/PhotoCurator; then
  fail "生产调用链仍包含旧调试上报"
fi

rg -q 'testEveryOpenAICompatibleCatalogModelBuildsImageRequest' \
  "$protocol_tests" ||
  fail "缺少全部兼容模型请求路由测试"
rg -q 'testArkAndMiniMaxUseSelectedCatalogModelID' "$protocol_tests" ||
  fail "方舟或 MiniMax 仍可能固定单一 model ID"
rg -q 'testVerificationUsesImageRequestAndFormalValidator' \
  "$verifier_tests" ||
  fail "缺少成功连接验证测试"
rg -q 'testVerificationRejectsResponseOutsideFormalContract' \
  "$verifier_tests" ||
  fail "缺少无效响应拒绝测试"
rg -q 'testModelVerificationIsPerModelAndClearsWithProvider' \
  Tests/PhotoCuratorTests/AIModelCatalogTests.swift ||
  fail "缺少具体模型验证状态测试"
rg -q 'testAdditionalProviderModelUsesRealModelIDIdentity' \
  Tests/PhotoCuratorTests/AIModelCatalogTests.swift ||
  fail "缺少其他 model ID 验证身份测试"
rg -q 'testOpenAIDiscoveryFiltersSpecializedAndSnapshotModels' \
  Tests/PhotoCuratorTests/AIModelDiscoveryServiceTests.swift ||
  fail "缺少 OpenAI 动态模型过滤测试"
rg -q 'testAnthropicDiscoveryUsesAccountDisplayNames' \
  Tests/PhotoCuratorTests/AIModelDiscoveryServiceTests.swift ||
  fail "缺少 Anthropic 动态模型发现测试"

for document in \
  AGENTS.md \
  README.md \
  docs/AI_BRAND_MODEL_CATALOG.md \
  docs/AI_MODEL_PROVIDERS.md \
  docs/AI_PROTOCOL_ADAPTERS.md \
  docs/DATA_CONTRACTS.md \
  docs/PRIVACY_POLICY.md \
  docs/PRODUCT.md \
  docs/TASKS.md; do
  rg -q '品牌' "$document" ||
    fail "$document 未记录品牌选择"
  rg -q '验证' "$document" ||
    fail "$document 未记录连接验证"
done

printf 'PC-34 检查通过：品牌与模型两级选择、34 个固定视觉模型、动态发现、其他 model ID 和真实连接验证一致。\n'
