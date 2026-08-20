# 供应商与协议适配

用户在「AI评分设置」中先选**品牌**，再选该品牌下已经真实接入、支持图片输入的模型，
并为该品牌保存自己的 API Key。本地分析、人工选片和复制导出继续不依赖 API Key。

完整的模型与 model ID 矩阵见[品牌与模型目录](MODEL_CATALOG.md)；
评分契约、排序与进度见 [AI评分](SCORING.md)。

## 设计前提：解析边界在协议，不在模型

模型目录与协议实现分离：

- **模型目录**负责供应商、显示名、API model ID、端点和能力标记；
- **协议适配器**负责图片输入、鉴权、结构化输出和响应 envelope；
- 所有适配器最终都返回 `AestheticReviewResult`，并必须通过同一个 `AestheticReviewValidator`。

之所以不逐模型写解析器：

1. 同一协议的模型共用请求和响应结构；
2. 模型差异只进入 descriptor/profile，例如 model ID、端点和少量扩展参数；
3. 业务 JSON 只有一个结构，最终只由 Validator 判断是否可用；
4. 新增同协议模型只需要目录项和契约测试，只有出现新协议时才新增适配器。

## 三个协议层

### Ark Responses

火山方舟使用 Responses API、`store=false`、强制工具调用和严格契约。

### OpenAI-compatible Chat Completions

OpenAI、Gemini、Qwen、xAI、Kimi、GLM、混元和自定义兼容接口共用一个适配器：

- `messages[].content` 中的 `text` 与 `image_url`；
- base64 内存 JPEG；
- 支持 JSON mode 的目录项使用 `response_format=json_object`，其他模型依靠严格 Prompt 与本地 Validator；
- `choices[].message.content` 与统一 usage；
- 安全机器错误码提取，随后本地 JSON 解码与正式校验。

MiniMax 通过同一协议族的专用 profile 发送 `thinking`、`reasoning_split`、`detail` 和
`max_long_side_pixel`，但不拥有独立的业务校验。

### Anthropic Messages

Claude 使用 `x-api-key` 与固定 `anthropic-version`、base64 `image` content block、
强制 `submit_photo_reviews` 工具，`tool_use.input` 转为统一 payload 后进同一个 Validator。

## 已核对的能力

- 现有方舟接入使用 Doubao-Seed-2.0 Lite，不是视频生成模型 Seedance。
- MiniMax-M3 支持图片输入、工具调用和关闭思考；M2.x 系列不支持图片输入，因此不进入评分模型目录。
- MiniMax-M3 使用 OpenAI-compatible Chat Completions，固定 `POST https://api.minimaxi.com/v1/chat/completions`。
- OpenAI、Gemini、Qwen 与 xAI 的官方文档均确认当前内置模型支持图片输入；
  Gemini 和 Qwen 同时提供 OpenAI 兼容接口。
- Claude 当前模型支持图片输入，使用 Messages API 的 base64 image block 与强制工具调用。

OpenAI 固定目录覆盖 GPT-5.6 Sol / Terra / Luna、GPT-5.5 和 GPT-5.4；
Anthropic 固定目录覆盖 Claude Fable 5、Opus 5 / 4.8 / 4.7 / 4.6 / 4.5、Sonnet 5 / 4.6 / 4.5 与 Haiku 4.5。
两家均可用 Key 刷新账号模型，并通过"其他模型 ID"接入固定目录之外的通用视觉模型；
模型列表发现只提供候选，不能代替图片连接验证。

## API Key

- 每个供应商使用独立 Keychain service/account；方舟沿用既有 service 名，升级后无需迁移。
- Key 不进入 UserDefaults、项目 JSON、日志、截图、诊断或导出。
- 新 Key 必须先用 1 张内置测试图走完正式图片请求、协议适配器与 Validator，
  **验证**成功后才写入 Keychain。验证失败不保存新 Key、不回显响应正文、不读取用户照片。
- 已验证的具体 model ID 作为非敏感偏好写入 UserDefaults；替换或删除品牌 Key 会清除该品牌所有
  model ID 的验证状态。

## 网络会话

所有供应商请求走同一个 ephemeral `URLSession`（`AIReviewURLSession.shared`）：
禁用磁盘 URLCache、Cookie 与凭据存储，请求超时 180 秒、资源超时 600 秒。
用 `URLSession.shared` 会把响应交给共享的磁盘缓存和 Cookie 存储，
和"AI 原始响应与供应商会话状态不落盘"的承诺冲突。

超时时间刻意高于系统默认的 60 秒：5 张 1536px 图片加结构化 JSON 输出在较慢的模型上会超过 60 秒，
而超时会触发自动重试，等于把同一批图片重新付费发一遍。

## 失败与重试

- HTTP 429、5xx 与网络中断按指数退避自动重试，最多 4 次，并优先遵守服务端返回的 `Retry-After`；
  被限流后同时抬高后续请求的间隔，避免下一批立刻再撞上同一堵墙。
- 鉴权失败、模型权限不足、模型 ID 错误和响应结构不兼容**不重试**——重试它们只会重复付费。
- 重试用尽后停在当前照片范围，已完成的评分与 token 统计保留，用户可以从中断处继续。
- MiniMax 普通按量 Key 与 `sk-cp` Token Plan 订阅 Key 都可保存，但计费资源不互通；
  Token Plan 受 5 小时/周额度及高峰期动态限流。其 HTTP 429 只映射为本地安全分类，
  不展示供应商 `message` 或响应正文。

## 自定义 OpenAI-compatible 接口

用户可配置显示名、完整 Chat Completions endpoint、API model ID 和独立 Keychain Key。规则：

- 远程地址必须为 HTTPS；仅 `localhost`、`127.0.0.1` 和 `::1` 可使用 HTTP。
- 地址不得包含用户名、密码、query 或 fragment，路径必须以 `/chat/completions` 结尾。
- 非敏感 endpoint、model ID 和显示名存入 UserDefaults；API Key 只进独立 Keychain 条目。
- App 不做静默模型探测，不发送额外计费请求；首次正式 AI评分即作为兼容性验证。
- 自定义接口返回不兼容结构时整批结果失效，不降低本地 Validator 要求。
- 自定义模型只承诺协议兼容，不标记为内置已验证模型。

## 不变的隐私与正确性边界

- 每张预览按用户确认的档位重编码为最长边 512px、1024px 或 1536px，只存在于内存中，
  不复制 EXIF/GPS、文件名或路径；默认 512px。
- 每次发送前必须取得确认。确认弹窗只用一句话说明模型、张数和照片类型；
  设置页展示品牌、模型、endpoint 与图片尺寸，侧栏 AI评分区常驻展示当前模型与尺寸档位。
- 模型对每张照片独立返回总分、五维分、具体评价和总结，禁止返回名次或相对措辞；
  缺图、重复 photo_id、分数越界或出现相对表述时本次结果整体失效。
- 不展示供应商原始响应、错误 message、request ID 或 Key。
- AI评分结果不自动改变 keep/reject；最终决定仍由用户完成。
