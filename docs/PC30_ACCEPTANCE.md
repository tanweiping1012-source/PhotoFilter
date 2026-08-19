# PC-30 视觉优先的相似照片策略验收

## 算法结论

旧策略存在实际问题：`BurstGrouper` 会把三秒内连续拍摄直接建立为候选家族，即使画面无关，也会折叠待评分候选并触发最终冲突。

当前策略已调整为：

- 画面感知哈希与亮度边界是建立相似关系的必要条件。
- 严格画面相似不依赖拍摄时间，可跨时间识别。
- 画面中等相似只有在两分钟内才视为同一场景。
- 时间接近但画面无关时，不分组、不折叠、不产生最终冲突。
- 拍摄时间继续用于时间线排序和普通照片的 AI 批次编排。

## 代码结果

- 生产分析不再调用纯时间 `BurstGrouper`，并清空旧 `burstGroup` 标记。
- `CandidateFamilyIndex` 只读取 `similarityGroup`。
- `LocalCandidateRanker` 只为画面相似照片生成一套本地建议。
- 最终结果冲突只检查画面相似家族。
- 内部旧字段与枚举保留用于兼容，但不再影响新分析。

## 用户表达

- 主界面、大图详情、无障碍文案和 String Catalog 只使用“相似照片”。
- 删除“连拍组”“相似组”“候选组”和“AI评分此组”等用户表达。
- AI评分只保留完整候选池入口，不提供单组相似照片局部评分。
- 大图只展示相似照片位置、技术风险和完整 AI评分结果。

## 自动验收

- `swift test`：100 项测试，0 失败。
- 新增同一时间但画面无关不分组测试。
- 新增旧时间标记不能建立家族或本地排序测试。
- `scripts/check-pc30.sh`：通过。
- String Catalog：393/393 英文完整，0 stale。

## 视觉验收

- `docs/interaction-screenshots/similar-photos-unified-zh-Hans.png`
- `docs/interaction-screenshots/first-curation-entry-zh-Hans.png`
- `docs/interaction-screenshots/first-curation-entry-en.png`

界面不再出现“连拍组”或重复的两套本地建议。
