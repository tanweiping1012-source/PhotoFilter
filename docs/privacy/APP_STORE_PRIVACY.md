# App Store 隐私披露对照

本文件用于填写 App Store Connect，并与 `Resources/PrivacyInfo.xcprivacy`、App 内“隐私与数据”及 `PRIVACY_POLICY.md` 保持一致。

## 建议答案

### Data Used to Track You

- **Tracking**：No
- **Tracking Domains**：None

### Data Linked to You

#### User Content → Photos or Videos

- **Collected**：Yes
- **Purpose**：App Functionality
- **Linked to the User**：Yes
- **Used for Tracking**：No

理由：只有用户确认品牌、模型、endpoint 域名、预览尺寸和照片数量后，候选预览才会发送给本次选择的火山方舟、MiniMax、OpenAI、Anthropic、Google、阿里云百炼、xAI、Kimi、智谱、腾讯混元或自定义兼容接口。验证 API Key 时还会发送 1 张 App 内置测试图，该图片不来自用户照片。预览最长边为用户选择的 512px、1024px 或 1536px。虽然使用匿名照片 ID，但请求携带用户自己的供应商 API Key，第三方处理方可能将调用关联到对应账号，因此按关联数据保守披露。

#### Identifiers → User ID

- **Collected**：Yes
- **Purpose**：App Functionality
- **Linked to the User**：Yes
- **Used for Tracking**：No

理由：用户自己的供应商 API Key 作为 Authorization 请求头发送给其选择的供应商服务。OpenAI / Anthropic 账号模型刷新也使用该 Key 读取模型 ID，但不发送图片。App 只把不同供应商 Key 分别保存在 Keychain，不发送给开发者后台。

### Other Data Types

以下类型当前均选择 **Not Collected**：

- Contact Info
- Health & Fitness
- Financial Info
- Location
- Sensitive Info
- Contacts
- Emails or Text Messages
- Audio Data
- Gameplay Content
- Customer Support
- Other User Content
- Browsing History
- Search History
- Device ID
- Purchases
- Product Interaction
- Advertising Data
- Other Usage Data
- Crash Data
- Performance Data
- Other Diagnostic Data
- Environment Scanning
- Body
- Other Data

## 本地数据不属于 App Store“收集”

以下数据不离开设备，不作为 App Store Privacy Nutrition Label 的 off-device collection：

- 原照片和本地文件路径；
- security-scoped bookmark；
- 相对路径人工决定、人物/风景目标和用户分类纠正；
- 缩略图缓存；
- 感知哈希、Apple Vision 自动人物主题判断、画面相似关系和技术风险；
- 导出清单；
- 通过模型响应得到的本地 AI评分结果。

## Privacy Manifest 对照

`PrivacyInfo.xcprivacy` 当前声明：

- `NSPrivacyTracking = false`
- `NSPrivacyCollectedDataTypePhotosorVideos`
  - linked：true
  - tracking：false
  - purpose：App Functionality
- `NSPrivacyCollectedDataTypeUserID`
  - linked：true
  - tracking：false
  - purpose：App Functionality
- `NSPrivacyAccessedAPICategoryFileTimestamp`
  - reason：`3B52.1`

`3B52.1` 对应读取用户通过系统文件夹选择器明确授权目录内的文件时间戳。App 使用拍摄时间缺失时的文件创建/修改时间进行本地时间线排序，并在画面中等相似时辅助判断是否来自同一场景；时间不能单独形成相似照片集合。

## 发布前核对

1. 确认所有内置供应商当前服务条款、数据处理协议以及方舟 `store=false` 行为未发生变化。
2. 在签名 Archive 上生成 Xcode Privacy Report，并与本文件逐项比较。
3. 将 `PRIVACY_POLICY.md` 发布到公开 HTTPS URL。
4. 在 App Store Connect 填写公开隐私政策 URL 和 App 支持 URL。
5. 若新增 SDK、日志、分析、崩溃上报或新的网络域名，先更新代码审计、Manifest、App 内文案和本文件。
