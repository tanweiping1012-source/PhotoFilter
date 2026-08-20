# 文档地图

先看 [README](../README.md) 了解这个 App 是什么。这里按"你想做什么"分类。

## 我想了解产品怎么设计的

| 文档 | 内容 |
|---|---|
| [产品说明](product/OVERVIEW.md) | **从这里开始。** 完整的产品行为定义：项目、筛选流程、导出规则、AI 边界 |
| [人物与风景分开筛选](product/CURATION_SCOPES.md) | 为什么分两条赛道，各自的目标、候选池与排序如何独立 |
| [人物主题本地分类](product/PEOPLE_CLASSIFICATION.md) | "人物照"的判定语义：清晰人像、显著剪影为什么算，背景路人为什么不算 |
| [相似照片识别策略](product/SIMILAR_PHOTOS.md) | 画面相似为主、时间只做辅助的分组规则 |
| [新手引导与第一次筛选教学](product/ONBOARDING.md) | 场景首页、八步离线教学、动态聚焦与完成出口 |

## 我想了解 AI评分

| 文档 | 内容 |
|---|---|
| [AI评分](ai/SCORING.md) | **从这里开始。** 独立评分、统一标尺、全局排序、进度表达、完成落点与查看路径 |
| [供应商与协议适配](ai/PROVIDERS.md) | BYOK、三个协议层、Keychain 隔离、网络会话与重试边界 |
| [品牌与模型目录](ai/MODEL_CATALOG.md) | 两级选择、内置模型清单、动态发现与连接验证 |
| [评分图片尺寸](ai/PREVIEW_SIZE.md) | 512 / 1024 / 1536 三档的取舍与确认要求 |
| [评分 JSON Schema](ai/REVIEW_SCHEMA.json) | 响应契约的机器可读定义 |

## 我要改代码

| 文档 | 内容 |
|---|---|
| [代码结构](engineering/ARCHITECTURE.md) | **从这里开始。** 模块地图、数据流、关键不变量、常见改动落点 |
| [开发与发布](engineering/DEVELOPMENT.md) | 从源码运行、门禁、基准测试、DMG 打包与 Release 流程 |
| [开发与运行 Harness](engineering/HARNESS.md) | 开发循环、运行时漏斗、各类门禁与必跑命令 |
| [数据契约](engineering/DATA_CONTRACTS.md) | 持久化字段、AI 请求/响应、导出清单的字段级定义 |
| [任务卡](engineering/TASKS.md) | 历史存档：PC-07 起每个任务当时的目标与验收口径，用于追溯设计原因，非当前行为定义 |
| [演示素材](engineering/DEMO_ASSETS.md) | 离线样例照片的生成方式与约束 |
| [项目规则](../AGENTS.md) | 改这个仓库前必读的硬约束 |

## 我要看隐私与上架

| 文档 | 内容 |
|---|---|
| [隐私政策](privacy/PRIVACY_POLICY.md) | 面向用户的隐私政策草案 |
| [App Store 隐私披露对照](privacy/APP_STORE_PRIVACY.md) | 提交表单逐项与代码行为的对照 |
| [App Review 离线演示](privacy/APP_REVIEW_DEMO.md) | 审核所需的离线演示步骤 |

## 截图

- [interaction-screenshots/](interaction-screenshots/)：中英双语的交互验收截图
- [store-screenshots/](store-screenshots/)：App Store 商店截图
