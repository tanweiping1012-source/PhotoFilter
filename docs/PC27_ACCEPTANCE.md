# PC-27 主流视觉模型与协议适配器验收

## 用户可见效果

AI评分设置当前提供：

- 火山方舟 · Doubao-Seed-2.0 Lite
- MiniMax · MiniMax-M3
- OpenAI · GPT-5.4 mini
- Anthropic · Claude Sonnet 5
- Google · Gemini 3.7 Flash
- 阿里云百炼 · Qwen3.8 Max
- xAI · Grok 4.6
- 自定义兼容接口 · OpenAI-compatible

每个供应商的 Key 独立保存、读取和删除。设置页显示 API model ID、供应商和 endpoint 域名；发送确认再次显示实际 endpoint。

## 架构验收

- OpenAI、Gemini、Qwen、xAI 和自定义模型共用 `OpenAICompatibleAestheticReviewClient`。
- Claude 使用 `AnthropicAestheticReviewClient`。
- Doubao 继续使用 Ark Responses。
- MiniMax 继续使用 OpenAI-compatible envelope 和其 `thinking/detail/max_long_side_pixel` 扩展。
- 所有协议都返回 `AestheticReviewResult` 并执行同一个 `AestheticReviewValidator`。
- 运行确认时锁定完整 model descriptor，包括自定义 endpoint 和 model ID；后续批次不会被设置变化替换。

因此新增同协议模型不需要新增解析器，只需目录项、profile 和测试；只有新的请求/响应协议才需要新适配器。

## 自定义兼容接口

- 保存显示名、完整 `/chat/completions` endpoint 和 model ID。
- 远程 endpoint 强制 HTTPS；HTTP 只允许 `localhost`、`127.0.0.1` 和 `::1`。
- 拒绝 URL 用户名、密码、query 和 fragment。
- endpoint、显示名和 model ID 存入 UserDefaults；API Key 只进入独立 Keychain。
- 首次正式 AI评分用于验证服务的图片与 JSON 兼容性，不额外发送探测请求。

## 自动与视觉验证

- 完整 Swift 测试：92 项，0 失败。
- OpenAI-compatible 测试覆盖 4 个内置供应商、图片 data URL、profile 参数、JSON 输出、usage 和安全错误码。
- Anthropic 测试覆盖 base64 image block、`x-api-key`、强制工具和 usage。
- 自定义配置测试覆盖安全 URL、回环 HTTP、持久化和请求路由。
- 353 个运行时 String Catalog 键全部有英文，0 stale。
- 中英文内置模型设置和自定义配置快照无截断。
- `scripts/check-pc27.sh`、隐私门禁和现有 PC-19 至 PC-26 门禁通过。

## 官方能力依据

2026 年 8 月 17 日核对：

- OpenAI image input 与模型目录：`platform.openai.com/docs`
- Anthropic vision、Messages tool use 与模型目录：`platform.claude.com/docs`
- Gemini 模型、图片输入与 OpenAI compatibility：`ai.google.dev/gemini-api/docs`
- 阿里百炼视觉 OpenAI 兼容与结构化输出：`help.aliyun.com/zh/model-studio`
- xAI image understanding、models 与 structured outputs：`docs.x.ai`

## 实际账号边界

本次没有使用用户 Key 对新增供应商发起真实计费请求。代码与本地契约已验收；模型可用性、地区网络、账号余额、模型权限和供应商临时变更以用户账号实际响应为准。
