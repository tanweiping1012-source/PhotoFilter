# AI 品牌、模型与连接验证规格

## 用户交互

AI评分设置拆成两个连续选择：

1. 选择品牌；
2. 选择该品牌下支持图片输入的具体模型。

品牌变化后，模型选择自动切换为该品牌的推荐默认项。模型与预览尺寸仍在 AI 任务确认时锁定，运行期间不可切换。

## 内置品牌

| 品牌 | 模型 |
| --- | --- |
| 火山方舟 | Doubao-Seed-2.1 Pro、Doubao-Seed-2.0 Lite |
| MiniMax | MiniMax-M3 |
| OpenAI | GPT-5.6 Sol、GPT-5.6 Terra、GPT-5.6 Luna、GPT-5.5、GPT-5.4、GPT-5.4 mini、GPT-5.4 nano、其他模型 ID |
| Anthropic | Claude Fable 5、Claude Opus 5 / 4.8 / 4.7 / 4.6 / 4.5、Claude Sonnet 5 / 4.6 / 4.5、Claude Haiku 4.5、其他模型 ID |
| Google Gemini | Gemini 3.1 Pro Preview、Gemini 3.7 Flash、Gemini 3.5 Flash-Lite |
| 阿里云百炼 | Qwen3.8 Max、Qwen3.7 Plus、Qwen3.7 Flash |
| xAI | Grok 4.6 |
| Kimi | Kimi K3、Kimi K2.6、Kimi K2.5 |
| 智谱 GLM | GLM-4.6V、GLM-4.6V-FlashX、GLM-4.6V-Flash |
| 腾讯混元 | Hunyuan Vision |
| 自定义兼容接口 | 用户输入 endpoint、model ID 与显示名 |

MiniMax 只列 M3，因为官方兼容文档明确 M3 支持图片输入，M2.x 系列仅支持文本。DeepSeek 当前官方 API 没有适用于本产品的图片理解模型，因此不进入照片评分选择器。百度千帆暂不加入内置目录：尚未核对到稳定的官方直接 API model ID、图片输入和结构化输出组合；用户仍可通过自定义 OpenAI-compatible 接口接入已验证的网关。

## 协议路由

- 火山方舟：Ark Responses。
- MiniMax：MiniMax OpenAI-compatible Chat 扩展。
- Anthropic：Messages API。
- OpenAI、Gemini、Qwen、xAI、Kimi、GLM、混元和自定义接口：OpenAI-compatible Chat。
- 所有模型最终必须返回统一的 `AestheticReviewContract v2`，并通过本地 Validator。

模型目录项必须声明：

- 稳定 App model ID；
- 品牌；
- 供应商 API model ID；
- endpoint；
- 协议与兼容 profile；
- 图片输入能力；
- 是否允许 `response_format=json_object`。

## API Key 验证

设置页不再把“写入 Keychain”视为配置成功。用户点击“验证并保存”后：

1. 使用当前品牌、模型和用户输入的 Key；
2. 读取 App Bundle 中 1 张无用户数据、无敏感信息的内置测试图；
3. 使用正式图片请求、正式 Prompt、正式协议适配器和正式 Validator 发起一次最小评分；
4. 只有完整链路成功，才把 Key 写入该品牌独立的 Keychain 条目；
5. 失败时不保存新 Key，只展示本地安全错误分类，不回显响应正文或 Key。

验证请求可能产生少量供应商费用，设置页必须在按钮前明确告知。已有 Key 可直接验证当前模型；切换同品牌模型不需要重复输入 Key，但新模型仍需单独验证。

验证状态按具体 model ID 记录为非敏感 UserDefaults 偏好。同品牌切换模型时复用 Key，但新模型验证成功前不能开始 AI评分；替换或删除该品牌 Key 时清除该品牌全部模型验证状态。

“连接成功”只代表当前时刻的 Key、账号权限、模型、endpoint、图片输入和 JSON 契约完整可用。后续仍可能因额度、限流、模型下线或网络状态失败。

## 动态模型发现

OpenAI 和 Anthropic 支持使用用户输入或已保存的品牌 Key 获取当前账号可见模型：

- OpenAI：`GET https://api.openai.com/v1/models`；
- Anthropic：`GET https://api.anthropic.com/v1/models?limit=1000`。

发现结果只用于减少手动输入，不直接声明图片能力。App 会过滤音频、转写、实时、图像生成、网络搜索、Codex/Cyber 等明显不属于通用图片理解的 OpenAI 专用模型；Anthropic 只接受 `claude-` 模型。用户从结果中选择后，该 ID 进入“其他模型 ID”，仍必须通过内置图片连接验证。

模型列表请求不保存 Key，不读取用户照片，也不把模型列表持久化。品牌内其他 model ID 和显示名属于非敏感配置，可写入 UserDefaults。验证标识使用 `品牌 + API model ID`，修改 model ID 后不会继承旧验证状态。

## 官方核对来源

- OpenAI 当前模型目录（GPT-5.6 Sol / Terra / Luna，图片输入）：https://developers.openai.com/api/docs/models
- OpenAI GPT-5.5（图片输入、Chat Completions）：https://developers.openai.com/api/docs/models/gpt-5.5
- Anthropic 模型与 Vision：https://platform.claude.com/docs/en/about-claude/models/overview
- Gemini 图片输入：https://firebase.google.cn/docs/ai-logic/analyze-images
- 火山方舟图片理解：https://www.volcengine.com/docs/82379/1362931
- MiniMax OpenAI 兼容与多模态：https://platform.minimax.io/docs/api-reference/text-openai-api
- 阿里云百炼视觉理解：https://help.aliyun.com/zh/model-studio/vision/
- Kimi Vision：https://platform.kimi.ai/docs/guide/use-kimi-vision-model
- 智谱 GLM-4.6V：https://docs.bigmodel.cn/cn/guide/models/vlm/glm-4.6v
- 腾讯混元 OpenAI 兼容与图生文：https://cloud.tencent.com/document/product/1729/111007
- xAI SDK 多图示例：https://github.com/xai-org/xai-sdk-python
