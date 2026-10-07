import SwiftUI

struct ContentView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(SteamAccountSession.self) private var steamSession
    @State private var activity = ActivityMonitor()
    @State private var window: NSWindow?
    @State private var enteredFullscreen = false
    @State private var isFullscreen = false
    @State private var pendingExitFullscreen = false
    @State private var wallLeavingFullscreen = false
    @State private var topInset: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var presentingWall: Bool { store.showingWall || wallLeavingFullscreen }
    var body: some View {
        @Bindable var store = store
        ZStack {
            Palette.background.ignoresSafeArea()
            if store.showingSetup {
                InitialSetupView(preferences: store.preferences).padding(.top, topInset)
            } else if presentingWall {
                PosterWallView().ignoresSafeArea().transition(.opacity)
            } else if let game = store.selectedGame {
                GameDetailView(gameID: game.id).transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    if store.destination == .home && store.search.isEmpty { HomeView(topInset: topInset) }
                    else { LibraryView().padding(.top, topInset) }
                }.transition(.opacity)
            }
            if let message = store.message {
                Text(message).font(.system(size: 12, weight: .medium)).padding(.horizontal, 22).padding(.vertical, 13)
                    .background(.regularMaterial, in: Capsule()).shadow(color: .black.opacity(0.2), radius: 15, y: 6)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 25).allowsHitTesting(false).transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if !store.showingSetup && !presentingWall {
                if store.selectedGame != nil || (store.destination == .home && store.search.isEmpty && store.heroGame != nil) {
                    Rectangle().fill(.ultraThinMaterial).frame(height: topInset + 16)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: topInset / (topInset + 16)), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .top) {
            if isFullscreen && !presentingWall { fullscreenToolbar }
        }
        .onPreferenceChange(FullscreenToolbarHeight.self) { height in
            if isFullscreen && height > 0 && abs(topInset - height) > 0.5 { topInset = height }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar { windowToolbar }
        .toolbar(presentingWall || isFullscreen ? .hidden : .visible, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: 900, minHeight: 640)
        .background(WindowReader(hidesToolbar: presentingWall || isFullscreen, onWindow: { window in
            self.window = window
            isFullscreen = window.styleMask.contains(.fullScreen)
            store.mainWindow = window
            activity.start(store: store, window: window)
        }, onTopInset: { inset in
            if inset > 0 && abs(topInset - inset) > 0.5 { topInset = inset }
        }))
        .preferredColorScheme(store.preferences.appearance == "跟随系统" ? nil : store.preferences.appearance == "浅色" ? .light : .dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: store.showingWall)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.selectedGame?.id)
        .task { steamSession.store = store; store.accountSession = steamSession; if !store.showingSetup { await store.scan() } }
        .onReceive(refreshTimer) { _ in
            if store.preferences.automaticRescan && NSApp.isActive && !store.showingWall && !store.showingSetup { Task { await store.scan() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusGameSearch)) { _ in
            store.selectedGame = nil; store.navigate(.library); searchFocused = true
        }
        .onChange(of: store.showingWall) { _, value in
            if value {
                enteredFullscreen = store.preferences.wallFullscreen && !(window?.styleMask.contains(.fullScreen) ?? false)
                if enteredFullscreen { window?.toggleFullScreen(nil) }
            } else {
                if enteredFullscreen {
                    // Keep the wall and detached toolbar until AppKit finishes
                    // leaving its fullscreen Space before restoring navigation.
                    wallLeavingFullscreen = true
                    if window?.styleMask.contains(.fullScreen) ?? false { window?.toggleFullScreen(nil) }
                    else { pendingExitFullscreen = true }
                }
                enteredFullscreen = false; activity.reset()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { notification in
            if notification.object as? NSWindow === window { isFullscreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            guard notification.object as? NSWindow === window else { return }
            isFullscreen = true
            if pendingExitFullscreen {
                pendingExitFullscreen = false; window?.toggleFullScreen(nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            if notification.object as? NSWindow === window {
                isFullscreen = false
                wallLeavingFullscreen = false; pendingExitFullscreen = false; enteredFullscreen = false
            }
        }
        .sheet(isPresented: $store.showingSteamLogin) { SteamLoginView().environment(steamSession) }
        .sheet(isPresented: $store.showingAddGame) { AddGameSheet().environment(store) }
        .sheet(isPresented: $store.showingCollections) { CollectionsSheet().environment(store) }
        .sheet(isPresented: $store.showingRemoved) { RecoverEntriesSheet().environment(store) }
        .sheet(isPresented: $store.showingUnlock) { UnlockHiddenSheet().environment(store) }
        .sheet(item: $store.editingLocalGame) { LocalArgumentsSheet(game: $0).environment(store) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in store.lockHidden() }
        .alert("暂时无法完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
    // AppKit places a native fullscreen toolbar in a separate opaque window.
    // Keeping this header in the content hierarchy lets the material sample art.
    private var fullscreenToolbar: some View {
        HStack(spacing: 14) {
            FullscreenWindowControls(window: window).frame(width: 60, height: 20)
            if store.selectedGame != nil && !store.showingSetup {
                Button { store.selectedGame = nil } label: {
                    HStack(spacing: 7) { Image(systemName: "chevron.left"); Text("返回游戏库") }
                        .font(.system(size: 12, weight: .medium)).frame(height: 34).contentShape(Rectangle())
                }.buttonStyle(.plain).keyboardShortcut(.escape, modifiers: [])
            } else {
                Text("Steam Game Launcher").font(.system(size: 13, weight: .semibold)).tracking(-0.25)
            }
            Spacer(minLength: 0)
            if !store.showingSetup {
                if let game = store.selectedGame {
                    Button { if game.isSteam { store.action(.store, game: game) } else { store.reveal(game) } } label: {
                        Label(game.isSteam ? "Steam 商店" : "在 Finder 中显示", systemImage: "arrow.up.right")
                            .font(.system(size: 12)).frame(height: 34).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                } else {
                    searchField
                    moreMenu
                    SettingsLink {
                        Image(systemName: "gearshape").font(.system(size: 16)).frame(width: 34, height: 34).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("设置 ⌘,")
                }
            }
        }
        .frame(minHeight: 34)
        .overlay {
            if store.showingSetup {
                Text("初始设置").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            } else if let game = store.selectedGame {
                Text(game.name).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 280)
            } else { destinationButtons }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: FullscreenToolbarHeight.self, value: geometry.size.height)
        })
    }
    @ToolbarContentBuilder private var windowToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if store.selectedGame != nil && !store.showingSetup {
                Button { store.selectedGame = nil } label: {
                    HStack(spacing: 7) { Image(systemName: "chevron.left"); Text("返回游戏库") }
                        .font(.system(size: 12, weight: .medium)).frame(height: 32).padding(.horizontal, 6).contentShape(Rectangle())
                }.keyboardShortcut(.escape, modifiers: [])
            } else {
                Text("Steam Game Launcher").font(.system(size: 13, weight: .semibold)).tracking(-0.25)
            }
        }
        ToolbarItem(placement: .principal) {
            if store.showingSetup {
                Text("初始设置").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            } else if let game = store.selectedGame {
                Text(game.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            } else if !presentingWall {
                destinationButtons
            }
        }
        if !store.showingSetup && !presentingWall {
            if let game = store.selectedGame {
                ToolbarItem(placement: .primaryAction) {
                    Button { if game.isSteam { store.action(.store, game: game) } else { store.reveal(game) } } label: {
                        HStack(spacing: 7) { Image(systemName: "arrow.up.right"); Text(game.isSteam ? "Steam 商店" : "在 Finder 中显示") }
                            .font(.system(size: 12)).frame(height: 32).padding(.horizontal, 6).contentShape(Rectangle())
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) { searchField }
                ToolbarItem(placement: .primaryAction) { moreMenu }
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Image(systemName: "gearshape").font(.system(size: 16)).frame(width: 34, height: 34).contentShape(Rectangle())
                    }.help("设置 ⌘,")
                }
            }
        }
    }
    private var destinationButtons: some View {
        HStack(spacing: 4) {
            ForEach(Destination.allCases, id: \.rawValue) { destination in
                Button { store.navigate(destination) } label: {
                    Text(destination.rawValue).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).frame(height: 32)
                        .foregroundStyle(store.destination == destination ? .primary : .secondary)
                        .background(store.destination == destination ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(destination.rawValue)
                    .accessibilityIdentifier("destination-\(destination.rawValue)")
            }
        }
    }
    private var searchField: some View {
        @Bindable var store = store
        return HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("搜索游戏", text: $store.search).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                    .accessibilityLabel("搜索游戏名称或 App ID")
                if !store.search.isEmpty {
                    Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 12).frame(width: 150, height: 34).background(.primary.opacity(0.045), in: Capsule())
    }
    private var moreMenu: some View {
        Menu {
                Button(store.saved.steamAccount == nil ? "登录 Steam…" : "Steam 账号…") { store.beginSteamLogin() }
                if store.saved.steamAccount != nil { Button("同步账号游戏库") { steamSession.refresh() }.disabled(steamSession.isSyncing) }
                Divider()
                Button("打开海报墙", systemImage: "rectangle.stack") { store.startWall() }
                Button("重新扫描", systemImage: "arrow.clockwise") { Task { await store.scan() } }.disabled(store.isScanning)
                Divider()
                ForEach(SteamLink.Destination.allCases) { destination in Button(destination.rawValue) { store.openSteam(destination) } }
                Divider()
                Button("添加 App ID…") { store.showingAddGame = true }
                Button("添加本地应用或文件…") { store.chooseLocalEntries() }
                Button("恢复入口…") { store.showingRemoved = true }
                Button("管理合集…") { store.showingCollections = true }
            } label: { Image(systemName: store.isScanning ? "hourglass" : "ellipsis").font(.system(size: 17)).frame(width: 34, height: 34).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 34).help("快捷操作")
    }
}

extension Notification.Name { static let focusGameSearch = Notification.Name("focusGameSearch") }

private struct FullscreenToolbarHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
