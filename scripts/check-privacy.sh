#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

manifest="Resources/PrivacyInfo.xcprivacy"
project_file="PhotoCurator.xcodeproj/project.pbxproj"
privacy_sources=(
  "$manifest"
  "Sources/PhotoCurator/PrivacyInformationView.swift"
  "docs/privacy/PRIVACY_POLICY.md"
  "docs/privacy/APP_STORE_PRIVACY.md"
)

fail() {
  printf '隐私检查失败：%s\n' "$1" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$manifest"
}

plutil -lint "$manifest" >/dev/null

[[ "$(plist_value NSPrivacyTracking)" == "false" ]] ||
  fail "NSPrivacyTracking 必须为 false"

[[ "$(plist_value NSPrivacyCollectedDataTypes:0:NSPrivacyCollectedDataType)" == "NSPrivacyCollectedDataTypePhotosorVideos" ]] ||
  fail "缺少照片或视频披露"
[[ "$(plist_value NSPrivacyCollectedDataTypes:0:NSPrivacyCollectedDataTypeLinked)" == "true" ]] ||
  fail "照片预览必须按供应商账号关联数据保守披露"
[[ "$(plist_value NSPrivacyCollectedDataTypes:0:NSPrivacyCollectedDataTypeTracking)" == "false" ]] ||
  fail "照片预览不得用于跟踪"
[[ "$(plist_value NSPrivacyCollectedDataTypes:0:NSPrivacyCollectedDataTypePurposes:0)" == "NSPrivacyCollectedDataTypePurposeAppFunctionality" ]] ||
  fail "照片预览用途必须为 App Functionality"

[[ "$(plist_value NSPrivacyCollectedDataTypes:1:NSPrivacyCollectedDataType)" == "NSPrivacyCollectedDataTypeUserID" ]] ||
  fail "缺少供应商账号标识披露"
[[ "$(plist_value NSPrivacyCollectedDataTypes:1:NSPrivacyCollectedDataTypeLinked)" == "true" ]] ||
  fail "供应商账号标识必须声明为关联数据"
[[ "$(plist_value NSPrivacyCollectedDataTypes:1:NSPrivacyCollectedDataTypeTracking)" == "false" ]] ||
  fail "供应商账号标识不得用于跟踪"

[[ "$(plist_value NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPIType)" == "NSPrivacyAccessedAPICategoryFileTimestamp" ]] ||
  fail "缺少文件时间戳 Required Reason API"
[[ "$(plist_value NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0)" == "3B52.1" ]] ||
  fail "用户授权目录的文件时间戳原因必须为 3B52.1"

rg -q 'PrivacyInfo\.xcprivacy in Resources' "$project_file" ||
  fail "PrivacyInfo.xcprivacy 未加入 Xcode Copy Bundle Resources"
rg -q 'PrivacyInformationView\.swift in Sources' "$project_file" ||
  fail "隐私界面未加入 Xcode Sources"
rg -q 'showPrivacyInformation = true' Sources/PhotoCurator/ContentView.swift ||
  fail "App 内缺少隐私入口"
rg -q 'creationDateKey.*contentModificationDateKey' Sources/PhotoCurator/PhotoMetadataReader.swift ||
  fail "代码已不再读取用户授权文件时间戳，请同步更新 Manifest"
rg -q 'store: false' Sources/PhotoCurator/ArkAestheticReviewClient.swift ||
  fail "方舟请求必须继续显式关闭存储"
rg -q 'thinking: MiniMaxThinking\(type: "disabled"\)' \
  Sources/PhotoCurator/MiniMaxAestheticReviewClient.swift ||
  fail "MiniMax-M3 请求必须关闭思考"
rg -q 'api\.minimaxi\.com/v1/chat/completions' Sources/PhotoCurator/AIModelCatalog.swift ||
  fail "MiniMax API 域名必须进入模型目录和隐私审计"
rg -q 'ark-api-key' Sources/PhotoCurator/AIProviderKeyStore.swift ||
  fail "必须保留现有方舟 Keychain service"
rg -q 'ai-api-key\.minimax' Sources/PhotoCurator/AIProviderKeyStore.swift ||
  fail "MiniMax 必须使用独立 Keychain service"
for service in \
  ai-api-key.openai \
  ai-api-key.anthropic \
  ai-api-key.google-gemini \
  ai-api-key.alibaba-model-studio \
  ai-api-key.xai \
  ai-api-key.moonshot-kimi \
  ai-api-key.zhipu-glm \
  ai-api-key.tencent-hunyuan \
  ai-api-key.custom-openai-compatible; do
  rg -q "$service" Sources/PhotoCurator/AIProviderKeyStore.swift ||
    fail "缺少独立 Keychain service：$service"
done
for provider in MiniMax OpenAI Anthropic Google 阿里云百炼 xAI Kimi 智谱 腾讯混元 自定义兼容接口; do
  rg -q "$provider" Sources/PhotoCurator/PrivacyInformationView.swift ||
    fail "App 内隐私说明必须披露 $provider"
done

if rg -n '/Users/|sk-[A-Za-z0-9_-]{8,}' "${privacy_sources[@]}"; then
  fail "隐私材料包含个人绝对路径或疑似明文 Key"
fi

printf '隐私检查通过：Manifest、App 内披露、数据对照与代码边界一致。\n'
