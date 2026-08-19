import AppKit
import SwiftUI

struct SupportInformationView: View {
    let isDemoModeActive: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var copiedDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("帮助与支持")
                    .font(.title2.weight(.bold))
                Text("常见问题与非敏感诊断信息")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("使用帮助") {
                    SupportHelpRow(
                        icon: "folder.badge.questionmark",
                        title: "文件夹权限",
                        detail: "权限失效时，点按项目并重新选择对应文件夹；App 不会尝试绕过系统授权。"
                    )
                    SupportHelpRow(
                        icon: "wand.and.stars",
                        title: "AI评分",
                        detail: "未配置 API Key 时，本地筛选与导出仍可使用。AI评分只会在你确认供应商、模型、图片尺寸和照片数量后开始。"
                    )
                    SupportHelpRow(
                        icon: "square.and.arrow.up",
                        title: "复制导出",
                        detail: "达到保留目标后可导出副本；原照片不会被移动、删除或修改。"
                    )
                }

                Section("诊断信息") {
                    Text("诊断信息仅包含 App 版本、macOS 版本和运行模式，不包含照片、文件路径或 API Key。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        copyDiagnostics()
                    } label: {
                        Label("复制诊断信息", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("support.copy-diagnostics")

                    if copiedDiagnostics {
                        Label("已复制不含照片、路径或 API Key 的诊断信息。", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("support.copy-status")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("support.information")
    }

    private func copyDiagnostics() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let mode = isDemoModeActive
            ? String(localized: "示例筛选")
            : String(localized: "本地项目")
        let productName = String(localized: "旅行照片筛选器")
        let diagnostics = [
            "\(productName) \(version) (\(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "\(String(localized: "运行模式")): \(mode)",
        ].joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        copiedDiagnostics = true
    }
}

private struct SupportHelpRow: View {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}
