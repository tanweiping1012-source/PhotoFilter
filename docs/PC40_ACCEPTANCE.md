# PC-40 产品名称统一验收

## 产品名称

- 简体中文：旅行照片筛选器
- 英文：Travel Photo Filter

## 覆盖范围

- App 窗口标题、系统显示名与 Bundle Name。
- 中英文 String Catalog、帮助页和诊断信息。
- 导出根目录、打包后的 `.app`、DMG 卷名与安装说明。
- Archive、DMG 默认文件名、README 和隐私政策。

## 工程兼容

`PhotoCurator` 继续作为内部 Swift 模块、Xcode Target、可执行文件和 Bundle ID 的一部分，不向普通用户展示，避免破坏升级、Keychain 和项目状态兼容性。

## 自动验收

- 旧产品名“旅行照片策展器”和 `Photo Curator` 不得出现在用户可见源码、资源、打包脚本或产品文档中。
- 简体中文和英文的 `CFBundleDisplayName`、`CFBundleName` 必须完整。
- 手工打包配置、Archive 与 DMG 默认文件名必须使用新产品名。
