import SwiftUI
import AppKit

@main struct SteamGameLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = LibraryStore()
    @State private var steamSession = SteamAccountSession()
    var body: some Scene {
        WindowGroup("Steam Game Launcher", id: "main") {
            ContentView().environment(store).environment(steamSession)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加 Steam 快捷入口…") { store.showingAddGame = true }.keyboardShortcut("n", modifiers: [.command])
                Button("添加本地应用或文件…") { store.chooseLocalEntries() }
                Button("恢复入口…") { store.showingRemoved = true }
                Button("添加游戏库…") { store.chooseFolder(asSteamRoot: false) }
            }
            CommandGroup(after: .toolbar) {
                Button("搜索游戏") { NotificationCenter.default.post(name: .focusGameSearch, object: nil) }.keyboardShortcut("f")
                Button("重新扫描") { Task { await store.scan() } }.keyboardShortcut("r").disabled(store.isScanning)
                Divider()
                Button("现在玩") { store.selectedGame = nil; store.navigate(.home) }.keyboardShortcut("1")
                Button("游戏库") { store.selectedGame = nil; store.navigate(.library) }.keyboardShortcut("2")
                Button("收藏") { store.selectedGame = nil; store.navigate(.favorites) }.keyboardShortcut("3")
                Divider()
                Button("海报墙") { store.startWall() }.keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu("Steam") {
                ForEach(SteamLink.Destination.allCases) { destination in Button(destination.rawValue) { store.openSteam(destination) } }
            }
        }
        Settings { SettingsView().environment(store).environment(steamSession) }
        MenuBarExtra("Steam Game Launcher", systemImage: "gamecontroller") {
            MenuBarView().environment(store)
        }
    }
}

struct MenuBarView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("打开 Steam Game Launcher") {
            if let window = store.mainWindow, window.isVisible || window.isMiniaturized {
                window.deminiaturize(nil); window.makeKeyAndOrderFront(nil)
            } else { openWindow(id: "main") }
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        if store.recentGames.isEmpty { Text("暂无最近游玩") }
        ForEach(Array(store.recentGames.filter(\.installed).prefix(5))) { game in
            Button { store.launch(game) } label: { Text(String(game.name.prefix(27))) }
        }
        Divider()
        Button("Steam 游戏库") { store.openSteam(.library) }
        Button("退出 Steam Game Launcher") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = NSApp.windows.first(where: { $0.title == "Steam Game Launcher" }) {
            window.deminiaturize(nil); window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
