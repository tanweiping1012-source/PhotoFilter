# 开发与发布

从源码运行、验证和打包的全部命令。模块地图与设计取舍见[代码结构](ARCHITECTURE.md)，
改动前的硬约束见[项目规则](../../AGENTS.md)。

需要 macOS 14+、Xcode 16.4 或更新版本，以及 ripgrep（`brew install ripgrep`，门禁脚本依赖它）。

开发用 Xcode 26 / Swift 6.2，CI 在 Xcode 16.4 / Swift 6.1.2 上跑同一条 `scripts/check.sh`。
两者的严格并发诊断有差异：`@MainActor` 类里覆写 `setUpWithError` 这类
nonisolated 方法并写入 actor 隔离的存储属性，6.2 接受、6.1.2 报错。
**本机编译通过不代表 CI 通过**，跨隔离域的写法要格外小心。

## 两套构建系统

新增源文件时**两边都要加**：

- `Package.swift`：`swift build` / `swift test` 用，跑单元测试和门禁；
- `PhotoCurator.xcodeproj`：产出真正的 `.app`（沙箱、entitlements、Info.plist、资源打包）。

测试文件只需要进 SwiftPM——它按目录 glob，不在 Xcode target 里。

## 运行

```bash
scripts/run-app.sh
```

先用内置的 8 张离线样例走一遍完整流程（不联网、不读 Keychain、不访问用户目录）：

```bash
scripts/run-app.sh --verification --review-demo
```

## 验证

```bash
scripts/check.sh
```

依次跑 `swift build`、`swift test`、隐私与演示门禁、20 个功能门禁，以及完整的 `xcodebuild`。
**每次改动后都要跑**；CI（`.github/workflows/ci.yml`）跑的是同一条命令，
不允许 CI 少跑其中任何一项。

想用真实照片跑性能基准或端到端验证（默认跳过，不会有照片进入仓库）：

```bash
PHOTO_BENCH_DIR=/path/to/photos swift test --filter "Benchmark|RealLibraryEndToEnd"
```

端到端测试会在筛选与导出前后逐文件比对大小和修改时间，用来守住"原图只读"。

## 打包

```bash
scripts/archive-app.sh          # Release 归档
scripts/package-dmg.sh          # 通用 DMG
```

`package-dmg.sh` 会先校验产物是 arm64 + x86_64 通用构建并通过 `codesign --verify`，
再生成带「应用程序」软链和安装说明的 DMG。

`scripts/*.sh` 必须保持可执行位（git mode 100755）：release 脚本一旦掉成 644，
文档里写的命令会直接 `Permission denied`。

## 发布

推送 `v*` 标签由 [`.github/workflows/release.yml`](../../.github/workflows/release.yml) 自动：

1. 跑完整 `scripts/check.sh`——没过门禁的构建不允许出现在 Release 页；
2. 归档并打通用 DMG；
3. 创建**草稿** Release 并附上 DMG，由人确认后再发布。

`dist/` 已被 `.gitignore` 排除，构建产物只作为 Release 资产存在，不进仓库。

提交 App Store 前仍需在 Xcode 中绑定 Apple Developer Team，
并使用对应的发行证书完成 Archive 分发签名与公证。

## 截图

`docs/interaction-screenshots/` 里的验收截图由 `scripts/render-*-snapshot.sh` 渲染，
参数为 `<输出路径> <语言> <宽> <高> <状态>`，宽高是**逻辑点**（脚本按 2x 输出）。
门禁会校验这些文件的精确像素尺寸。
