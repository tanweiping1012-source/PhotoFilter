# AI 模型供应商架构

## 目标效果

用户在“AI评分设置”中先选择品牌，再选择该品牌已经真实接入的视觉模型，并为该品牌保存自己的 API Key。当前品牌覆盖火山方舟、MiniMax、OpenAI、Anthropic、Google Gemini、阿里百炼、xAI、Kimi、智谱 GLM、腾讯混元与自定义 OpenAI-compatible；完整模型矩阵见 [AI_BRAND_MODEL_CATALOG.md](AI_BRAND_MODEL_CATALOG.md)。

本地分析、人工选片和复制导出继续不依赖 API Key。模型选择器不展示尚未实现或不支持图片输入的模型。用户输入的新 Key 必须使用内置测试图走完真实图片请求与统一 Validator，成功后才保存。

OpenAI 固定目录覆盖 GPT-5.6 Sol / Terra / Luna、GPT-5.5 和 GPT-5.4 三档；Anthropic 固定目录覆盖 Claude Fable 5、Opus 5 / 4.8 / 4.7 / 4.6 / 4.5、Sonnet 5 / 4.6 / 4.5 与 Haiku 4.5。两家均可用 Key 刷新账号模型，并通过“其他模型 ID”接入固定目录之外的通用视觉模型；模型列表发现不代替图片连接验证。

## 已核对能力

- 现有方舟接入使用 Doubao-Seed-2.0 Lite，不是视频生成模型 Seedance。
- MiniMax-M3 支持图片输入、工具调用和关闭思考。
- MiniMax M2.x 系列不支持图片输入，因此不进入照片评分模型目录。
- MiniMax-M3 使用 OpenAI-compatible Chat Completions；第一版面向当前中国区用户环境，固定 `POST https://api.minimaxi.com/v1/chat/completions`。
- OpenAI、Gemini、Qwen 与 xAI 的官方文档均确认当前内置模型支持图片输入；Gemini 和 Qwen 同时提供 OpenAI 兼容接口。
- Claude 当前模型支持图片输入，使用 Anthropic Messages API 的 base64 image block 与强制工具调用。

## 组件边界

### `AIModelCatalog`

- 使用稳定的内部 model ID，外部 API model ID 作为目录配置。
- 每项模型声明供应商、显示名、API model ID、端点、协议 profile 和图片能力。
- 只有具备图片能力且存在适配器的模型才出现在 Picker。

### 模型选择

- 选中的 model ID 存入 UserDefaults；它不包含秘密，也不进入照片项目状态。
- 默认保持现有 Doubao 模型，升级后不会突然把请求切到其他供应商。
- 组内与整轮 AI评分在确认时复制 model ID；运行中设置变化不影响该轮任务。

### API Key

- 每个供应商使用独立 Keychain service/account。
- 现有方舟 service 名保持不变，避免升级后丢失已保存 Key。
- MiniMax、OpenAI、Anthropic、Google、阿里百炼、xAI 与自定义接口各使用独立 service；Key 不进入 UserDefaults、项目 JSON、日志、截图、诊断或导出。

### 供应商适配器

- 输入统一为 `AestheticReviewRequest` 与内存 JPEG 预览。
- 方舟适配器继续使用 Responses API。
- MiniMax 适配器使用 OpenAI-compatible Chat Completions；发送 base64 JPEG，将小/中/大映射为 `detail=low/default/high` 与对应 `max_long_side_pixel`，关闭思考，并接受工具调用参数或纯 JSON 文本。
- OpenAI、Google、阿里百炼、xAI 与自定义模型复用一个 OpenAI-compatible Chat 适配器。
- Anthropic 适配器使用 Messages API 和强制工具调用。
- 所有适配器都返回统一 `AestheticReviewResult`，再经过现有 `AestheticReviewValidator`。
- MiniMax 普通按量 API Key 与 `sk-cp` Token Plan 订阅 Key 都可保存，但两类 Key 的计费资源不互通。Token Plan 受 5 小时/周额度及高峰期动态限流。
- MiniMax HTTP 429 只映射为本地安全分类，不展示供应商 `message` 或响应正文；Token Plan 用户会被引导检查套餐用量或至少等待一分钟后重试。
- HTTP 429 不自动重试，避免在额度或动态限流期间继续增加请求；失败批次继续保留给用户手动重试。

## 不变的隐私与正确性边界

- 每张预览按用户确认的档位重编码为最长边 512px、1024px 或 1536px，只存在于内存中，不复制 EXIF/GPS、文件名或路径；默认 512px。
- 每次发送前显示供应商、模型、照片数和数据边界并取得确认。
- 模型必须返回完整唯一排名、0–100 分和短理由；任何缺图、重复、越界或跨组结果整体失效。
- AI评分结果不自动改变 keep/reject；最终决定仍由用户完成。
- 失败诊断只展示 HTTP 状态、短机器错误码和失败阶段，不回显供应商原始正文。

## 扩展其他模型

同协议模型优先通过目录项或自定义 OpenAI-compatible 配置接入。只有供应商使用新的请求/响应 envelope 时才新增协议适配器；任何新增内置模型仍需图片能力验证、Keychain 隔离、契约测试和隐私披露。

详细协议边界见 `AI_PROTOCOL_ADAPTERS.md`。
