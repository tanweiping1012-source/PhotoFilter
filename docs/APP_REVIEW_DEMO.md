# App Review 离线演示

## 审核步骤

1. 启动 App。
2. 在左侧点按“新手引导”，然后选择“体验一次完整筛选”。
3. App 载入 4 张人物和 4 张风景，目标固定为各 2 张，并显示八步任务条。
4. 选择“人物”，打开任意人物照片并标记为“保留”，再点按“演示 AI评分”。界面按已评估照片数逐步显示两类固定结果，全程不联网。
5. 选择“风景”，打开一张已评分风景照片，检查总分、五维评分、具体评价和 AI总结。
6. 回到“全部”，将状态筛选切换为“评分优先”，采纳其余 3 张结果，使人物和风景各保留 2 张。
7. 点按“导出人物与风景 4 张”，选择任意可写目录并确认。App 将样例分别复制到“人物”和“风景”子目录，并生成根 JSON/CSV 清单。
8. 点按“结束新手引导”正常退出；示例项目不会跨重启保存。

## 审核边界

- 不需要火山方舟 API Key。
- 不读取 macOS Keychain。
- 不发起任何网络请求。
- 不打开文件夹选择器，不读取用户目录。
- 固定 AI 结果仍通过正式 `AestheticReviewValidator`、`AestheticReviewApplier` 和最终数量校验。
- 演示中的人工决定和导出行为与真实项目使用相同代码路径。
- 演示素材来源与完整性见 `DEMO_ASSETS.md`。

## App Review Notes 草案

### 中文

本 App 的核心筛选与导出功能可完全离线使用。请在左侧点按“新手引导”，再选择“体验一次完整筛选”，即可在真实界面中完成选择人物、打开大图、人工保留、人物/风景分别评分、切换风景、查看评分、采纳结果和双目录复制导出。4 张人物与 4 张风景初始没有评分；只有审核员主动点按“演示 AI评分”后，固定结果才会按已评估照片数逐步出现。该模式不读取 Keychain、不联网、不访问用户目录，也不需要测试账号或 API Key。真实 AI评分为可选 BYOK，只有用户选择已实现的视觉模型、选择小/中/大图片尺寸、配置对应供应商 API Key 并确认发送后才会联网。

### English

The app's core curation and export workflow works fully offline. Click "新手引导" (Getting Started) in the left sidebar, then choose "体验一次完整筛选" (Try a Complete Curation). The real interface guides the reviewer through selecting People, opening a large preview, keeping one photo, running separate offline scoring for People and Scenery, switching to Scenery, reviewing score details, accepting the remaining results, and exporting copies into two folders. The four People and four Scenery samples start without scores; fixed results appear only after the reviewer clicks "演示 AI评分" (Demo AI Scoring). This mode does not access Keychain, connect to the network, read user folders, or require a test account or API key. Live AI scoring is optional BYOK and connects only after the user selects an implemented vision model, chooses a Small/Medium/Large image size, provides the matching provider API key, and confirms transmission.

## 自动启动

内部验收可使用启动参数直接进入演示：

```bash
PhotoCurator.app/Contents/MacOS/PhotoCurator --review-demo
```

公开审核说明应使用可见的“新手引导”入口，不要求审核员输入命令。
