# PC-28 可解释 AI评分详情验收

## 交付结果

- 每条有效评分包含总分、瞬间/构图/主体/光线/叙事表现五维分、1–3 条具体评价和 AI总结；完整一轮结束后由 App 计算全局名次。
- “待AI评分”只显示尚无有效评分的候选；“已AI评分”显示全部评分照片；“评分优先”只显示整轮最终胜出集合。
- 照片卡只显示主总分。完整一轮评分优先作为主总分，没有完整一轮记录时使用最后一条手动评分。
- 选中已评分照片后，宽布局显示“查看评分”，920px 紧凑布局显示“评分”；两者复用同一大图预览。
- 大图右侧按阶段分段显示评分详情，左右键继续按打开时的筛选结果浏览。
- 同一照片的手动评分和完整一轮评分同时保留；相同 scope 的重新评分会替换旧记录。

## 契约与协议

- `AestheticReviewEntry` 和 `AestheticRecommendation` 已加入 `AestheticScoreDimensions` 与 `summary`。
- 本地 Validator 校验五维 0–100、具体评价 1–3 条/每条 2–80 字，以及总结 4–120 字；任一字段不合法则整组失效。
- 方舟 Responses、MiniMax Chat Completions、Anthropic Messages 工具 schema 和 OpenAI-compatible JSON Prompt 均要求完整评分详情。
- 最大输出 token 从 720 调整为 1600，为最多 5 张照片的闭合 JSON 预留空间；实际用量仍由供应商按返回内容计算。
- 离线样例的 8 张照片均包含固定评分详情，其中 4 张为评分优先；不读取 Keychain、不联网、不持久化评分。

## 自动验收

- `swift test`：96 项测试，0 失败。
- `scripts/check-pc28.sh`：通过。
- `scripts/check.sh`：通过。
- Xcode Debug 构建：`BUILD SUCCEEDED`。
- String Catalog：372/372 英文完整，0 stale。
- 未使用用户 API Key 发起任何新增计费请求。

## 视觉验收

- `docs/interaction-screenshots/ai-scored-grid-zh-Hans-920x640.png`
- `docs/interaction-screenshots/ai-scored-grid-en-920x640.png`
- `docs/interaction-screenshots/photo-score-details-zh-Hans.png`
- `docs/interaction-screenshots/photo-score-details-en.png`

中英文网格和评分详情均无截断、重叠或错误“待评分”标记。
