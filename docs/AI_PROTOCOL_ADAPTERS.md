# AI 协议适配器规格

## 目标

让用户选择主流视觉模型，同时避免为每个模型复制请求、响应和校验代码。

模型目录与协议实现分离：

- 模型目录负责供应商、显示名、API model ID、端点和协议能力。
- 协议适配器负责图片输入、鉴权、结构化输出和响应 envelope。
- 所有适配器最终返回 `AestheticReviewResult`，并必须通过同一个 `AestheticReviewValidator`。

## 内置模型

设置页先选择品牌，再选择该品牌下支持图片输入的模型。内置品牌为火山方舟、MiniMax、OpenAI、Anthropic、Google Gemini、阿里云百炼、xAI、Kimi、智谱 GLM、腾讯混元与自定义兼容接口；完整模型与 model ID 矩阵见 [AI_BRAND_MODEL_CATALOG.md](AI_BRAND_MODEL_CATALOG.md)。

同品牌可包含旗舰、平衡和高速模型，但纯文本模型不进入照片评分目录。模型可用性、账号权限和价格仍以供应商为准。

## 协议层

### Ark Responses

保留现有方舟实现、`store=false`、工具调用和严格契约。

### OpenAI-compatible Chat

OpenAI、Gemini、Qwen、xAI、Kimi、GLM、混元和自定义兼容接口共用：

- `messages[].content` 中的 `text` 与 `image_url`；
- base64 内存 JPEG；
- 支持 JSON mode 的目录项使用 `response_format=json_object`；其他模型依靠严格 Prompt 与本地 Validator；
- `choices[].message.content` 与统一 usage；
- 安全机器错误码提取；
- 本地 JSON 解码与正式 Validator。

MiniMax 继续通过同一协议族的专用 profile 发送 `thinking`、`reasoning_split`、`detail` 和 `max_long_side_pixel`，但不拥有独立业务校验。

### Anthropic Messages

Claude 使用：

- `x-api-key` 与固定 `anthropic-version`；
- base64 `image` content block；
- 强制 `submit_photo_reviews` 工具；
- `tool_use.input` 转为统一 payload；
- 同一个正式 Validator。

## 自定义 OpenAI-compatible

用户可配置：

- 显示名；
- 完整 Chat Completions endpoint；
- API model ID；
- 独立 Keychain API Key。

配置规则：

- 远程地址必须为 HTTPS；仅 `localhost`、`127.0.0.1` 和 `::1` 可使用 HTTP。
- 地址不得包含用户名、密码、query 或 fragment。
- 非敏感 endpoint、model ID 和显示名存入 UserDefaults。
- API Key 只进入自定义供应商的独立 Keychain 条目。
- App 不做静默模型探测，不发送额外计费请求；首次正式 AI评分即作为兼容性验证。
- 自定义接口返回不兼容结构时，整批结果失效，不降低本地 Validator 要求。

## 为什么不是逐模型解析

解析边界在协议 envelope，而不在模型：

1. 同一协议的模型共用请求和响应结构。
2. 模型差异只进入 descriptor/profile，例如 model ID、端点和少量扩展参数。
3. 业务 JSON 只有一个结构，最终只由 `AestheticReviewValidator` 判断是否可用。
4. 新增同协议模型只需目录项和契约测试；只有出现新协议时才新增适配器。

## 隐私与失败边界

- 每批仍只发送用户确认的 2–5 张匿名无元数据 JPEG。
- 不发送原图、文件名、本地路径或 EXIF/GPS。
- 每个供应商 Key 相互隔离。
- 设置和确认弹窗显示实际供应商、模型、图片尺寸和数量。
- 自定义 endpoint 域名在发送确认中明确展示。
- 不展示供应商原始响应、错误 message、request ID 或 Key。
- HTTP、权限、限流和兼容性错误不自动重试。
