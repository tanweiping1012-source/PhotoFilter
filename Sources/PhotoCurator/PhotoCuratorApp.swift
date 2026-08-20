import AppKit
import SwiftUI

@main
struct PhotoCuratorApp: App {
    @StateObject private var library = PhotoLibraryViewModel()

    var body: some Scene {
        WindowGroup("旅行照片筛选器") {
            ContentView()
                .environmentObject(library)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    library.prepareForTermination()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandMenu("选片") {
                // 快捷键必须和底部命令条、大图预览用同一把锁：一轮评分只锁它自己那一类，
                // 否则风景在评分时连人物照片的 P / X / U 都按不动。
                Button("保留") { library.markSelected(as: .keep) }
                    .keyboardShortcut("p", modifiers: [])
                    .disabled(!library.canDecideSelectedPhoto)
                Button("淘汰") { library.markSelected(as: .reject) }
                    .keyboardShortcut("x", modifiers: [])
                    .disabled(!library.canDecideSelectedPhoto)
                Button("恢复待定") { library.markSelected(as: .undecided) }
                    .keyboardShortcut("u", modifiers: [])
                    .disabled(!library.canDecideSelectedPhoto)
                Divider()
                Button("撤销标记") { library.undo() }
                    .keyboardShortcut("z")
                    .disabled(!library.canUndo)
            }
        }
    }
}
