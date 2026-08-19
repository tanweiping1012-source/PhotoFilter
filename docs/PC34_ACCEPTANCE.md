# PC-34 AI 品牌、模型与连接验证验收

## 交付结果

- AI评分设置拆为“品牌”和“模型”两个 Picker。
- 内置 11 个品牌、34 个固定视觉模型，并提供 OpenAI 其他模型、Anthropic 其他模型和自定义兼容接口 3 个灵活入口。
- 品牌变化后自动切换到该品牌推荐模型；运行中继续锁定品牌、模型和预览尺寸。
- 同品牌模型复用品牌 Keychain Key，但每个具体 model ID 必须单独验证。
- 替换或删除品牌 Key 时，会清除该品牌全部模型的验证状态。

## 品牌与模型

- 火山方舟：Doubao-Seed-2.1 Pro、Doubao-Seed-2.0 Lite。
- MiniMax：MiniMax-M3。
- OpenAI：GPT-5.6 Sol、GPT-5.6 Terra、GPT-5.6 Luna、GPT-5.5、GPT-5.4、GPT-5.4 mini、GPT-5.4 nano和其他模型 ID。
- Anthropic：Claude Fable 5、Claude Opus 5 / 4.8 / 4.7 / 4.6 / 4.5、Claude Sonnet 5 / 4.6 / 4.5、Claude Haiku 4.5和其他模型 ID。
- Google Gemini：Gemini 3.1 Pro Preview、Gemini 3.7 Flash、Gemini 3.5 Flash-Lite。
- 阿里云百炼：Qwen3.8 Max、Qwen3.7 Plus、Qwen3.7 Flash。
- xAI：Grok 4.6。
- Kimi：Kimi K3、Kimi K2.6、Kimi K2.5。
- 智谱 GLM：GLM-4.6V、GLM-4.6V-FlashX、GLM-4.6V-Flash。
- 腾讯混元：Hunyuan Vision。
- 自定义 OpenAI-compatible：用户配置 endpoint、model ID 和显示名。

纯文本模型不进入照片评分选择器。DeepSeek 当前官方 API 没有适用于本产品的图片理解模型，因此未伪装成可选项。

## 动态模型

- OpenAI 与 Anthropic 可使用当前输入或已保存 Key 刷新账号可见模型。
- OpenAI 发现结果会过滤音频、实时、转写、图像生成、搜索、Codex/Cyber、Pro 和日期快照等不适合当前 Chat 图片评分链路的模型。
- Anthropic 发现结果只接受账号返回的 `claude-` 模型。
- 模型列表不持久化，也不上传图片；用户选中的其他 model ID 和显示名作为非敏感配置保存。
- 账号可见不等于支持照片评分，选中后仍必须使用内置测试图完成正式连接验证。

## 连接验证

- “验证并保存”使用 1 张 App Bundle 内置测试图发起正式图片评分请求。
- 请求经过当前模型 endpoint、真实协议适配器、图片输入、Prompt、响应解析和 `AestheticReviewValidator`。
- 只有完整链路成功，新 Key 才写入该品牌独立 Keychain。
- 已保存 Key 可验证当前模型；验证失败不覆盖 Key，不记录 model ID 为已验证。
- 连接验证可能产生少量供应商费用，设置页和隐私材料均已披露。
- 清理了 MiniMax DEBUG 版遗留的 `127.0.0.1:7777` 调试上报。

## 验收结果

- `swift test`：113 项测试，0 失败。
- 全部 OpenAI-compatible 目录模型均通过图片请求构造测试。
- 方舟和 MiniMax 已验证使用当前 descriptor 的 model ID，不再固定单一模型。
- 连接验证器包含成功和正式契约失败两类 mock 网络回归。
- String Catalog：427/427 英文完整，0 stale。
- 隐私、演示、PC-19 至 PC-34 门禁全部通过。
- Xcode Debug：`BUILD SUCCEEDED`。
- 未使用用户 API Key 发起真实付费请求；真实连通性由 App 在用户点击验证时逐模型确认。

## 界面快照

- 中文：`docs/interaction-screenshots/ai-brand-model-settings-zh-Hans.png`
- 英文：`docs/interaction-screenshots/ai-brand-model-settings-en.png`
- OpenAI 中文：`docs/interaction-screenshots/ai-openai-models-zh-Hans.png`
- OpenAI 英文：`docs/interaction-screenshots/ai-openai-models-en.png`
- Anthropic 其他模型中文：`docs/interaction-screenshots/ai-anthropic-other-model-zh-Hans.png`
- Anthropic 其他模型英文：`docs/interaction-screenshots/ai-anthropic-other-model-en.png`
