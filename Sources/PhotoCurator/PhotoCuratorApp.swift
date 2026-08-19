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
                Button("保留") { library.markSelected(as: .keep) }
                    .keyboardShortcut("p", modifiers: [])
                    .disabled(library.selectedPhoto == nil || library.isAIFinalSelectionRunActive)
                Button("淘汰") { library.markSelected(as: .reject) }
                    .keyboardShortcut("x", modifiers: [])
                    .disabled(library.selectedPhoto == nil || library.isAIFinalSelectionRunActive)
                Button("恢复待定") { library.markSelected(as: .undecided) }
                    .keyboardShortcut("u", modifiers: [])
                    .disabled(library.selectedPhoto == nil || library.isAIFinalSelectionRunActive)
                Divider()
                Button("撤销标记") { library.undo() }
                    .keyboardShortcut("z")
                    .disabled(!library.canUndo)
            }
        }
    }
}
