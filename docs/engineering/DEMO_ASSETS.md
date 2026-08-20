# 新手引导与审核样例素材

## 来源与权利

`Resources/DemoPhotos` 中的 8 张 JPEG 由本仓库的 `scripts/generate-demo-photos.swift` 使用 AppKit/Core Graphics 程序化绘制。

- 不包含用户照片或真实旅行照片。
- 不使用外部图片、图库、品牌素材或第三方版权内容。
- 前 4 张包含程序化绘制的抽象人物主体，后 4 张为风景；人物不对应任何真实身份或人脸。
- 不包含品牌、Logo、车牌或可读文字。
- 不包含 GPS、相机、作者或真实拍摄时间元数据。
- 生成器和输出均属于本项目发行资产，可随 App 分发并供 App Review 使用。

## 可复现性

重新生成：

```bash
tmp_binary="$(mktemp -u /tmp/photo-curator-demo-generator.XXXXXX)"
xcrun swiftc -parse-as-library scripts/generate-demo-photos.swift -o "$tmp_binary"
"$tmp_binary" Resources/DemoPhotos
rm -f "$tmp_binary"
```

生成后运行：

```bash
bash scripts/check-demo.sh
```

检查会核对文件数量、尺寸、固定 SHA-256、Xcode Bundle 接线，以及演示业务代码中不存在 Keychain 或网络 API。

## 用途

这些图片只用于离线演示人物/风景分流、浏览、固定分类 AI评分详情、人工采纳和双目录复制导出。它们不是产品能力或真实拍摄质量的宣传样片。
