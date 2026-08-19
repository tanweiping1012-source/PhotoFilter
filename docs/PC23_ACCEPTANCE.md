# PC-23 可调 AI 预览尺寸验收

## 用户可见效果

- AI 设置用分段控件展示“小 / 中 / 大”，并显示当前档位的精确最长边。
- 小为 512px，默认用于整体构图；中为 1024px，用于多人照片和一般细节；大为 1536px，用于远景、小主体、表情和纹理。
- 设置页明确提示：更大的图片可能提高细节识别，也会增加上传量、等待时间和供应商费用。
- 当前档位作为全局偏好保存；旧版本没有该偏好时继续使用小档。
- 组内和整轮 AI评分的确认弹窗均显示已锁定的供应商、模型、档位、像素和照片数量。
- AI 任务运行期间禁止修改模型与尺寸，自动重试和后续批次继续使用确认时的档位。

## 请求与隐私边界

- 三档都只生成内存 JPEG，不发送原图、文件名、路径或 EXIF/GPS。
- 火山方舟接收按 512/1024/1536px 边界重编码的图片。
- MiniMax-M3 同步发送 `detail=low/default/high` 和 `max_long_side_pixel=512/1024/1536`。
- 1536px 多图编码通过 `Task.detached` 在后台执行，避免阻塞主线程。
- App 内隐私说明、公开隐私政策、App Store 披露、数据契约、README 和 DMG 安装说明已同步更新。

## 自动与视觉验证

- 完整 Swift 测试：92 项，0 失败。
- 三档实际 JPEG 最长边分别验证为 512、1024、1536px。
- 高分辨率预览验证不复制 GPS metadata。
- MiniMax 大档验证 `detail=high` 和 `max_long_side_pixel=1536`。
- 尺寸偏好验证默认值和 UserDefaults round-trip。
- `scripts/check.sh` 全部通过，包括隐私、Demo、PC-19、PC-21、PC-22、PC-23 和 Xcode Debug 构建。
- 中英文 AI评分设置页离屏快照通过；当前 353 个运行时 String Catalog 键均有英文译文。

## 交付校验

- 版本：0.4.0。
- 通用 Archive：`dist/PhotoCurator-PC23-final.xcarchive`。
- 非公证 DMG：`dist/PhotoCurator-0.4.0-macOS-universal.dmg`。
- 架构：`x86_64 + arm64`。
- 签名：本地 ad-hoc `Sign to Run Locally`，`codesign --verify --deep --strict` 通过。
- 权限：App Sandbox、出站网络、app-scoped bookmark 和用户选择目录权限存在。
- 资源：Privacy Manifest 有效，中英文本地化已编译，8 张 Demo 图片与 SHA-256 清单一致。
- DMG 完整性：`hdiutil verify` 通过。
- DMG SHA-256：`a4d03d8c298b423616156c8badbdd555f577ccaba1d416da344478207d7da518`。

此版本未使用用户 API Key 发起真实计费请求。由于未购买 Apple Developer Program，DMG 未使用 Developer ID 签名且未公证，首次启动仍需按安装说明手动放行。
