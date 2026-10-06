import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(SteamAccountSession.self) private var steamSession
    @State private var showingPassword = false
    @State private var confirmingReset = false
    var body: some View {
        TabView {
            account.tabItem { Label("Steam 账号", systemImage: "person.crop.circle") }
            general.tabItem { Label("通用", systemImage: "slider.horizontal.3") }
            libraries.tabItem { Label("游戏库", systemImage: "externaldrive") }
            privacy.tabItem { Label("隐私", systemImage: "lock") }
            wall.tabItem { Label("海报墙", systemImage: "rectangle.stack") }
            about.tabItem { Label("关于", systemImage: "info.circle") }
        }.padding(16).frame(width: 720, height: 590)
            .sheet(isPresented: $showingPassword) { HiddenPasswordSheet().environment(store) }
            .confirmationDialog("还原初始设置？", isPresented: $confirmingReset) {
                Button("还原初始设置") { store.restorePreferences() }
            } message: { Text("还原外观、扫描位置、启动和海报墙设置。收藏、入口、隐藏状态与密码会保留。") }
            .preferredColorScheme(store.preferences.appearance == "跟随系统" ? nil : store.preferences.appearance == "浅色" ? .light : .dark)
    }
    private var account: some View {
        Form {
            Section("Steam 账号") {
                if let account = store.saved.steamAccount {
                    LabeledContent("账号", value: account.displayName)
                    LabeledContent("SteamID", value: account.steamID)
                    LabeledContent("账号游戏库", value: "\(account.games.count) 款游戏")
                    LabeledContent("上次同步", value: account.syncedAt.formatted(date: .abbreviated, time: .shortened))
                    HStack {
                        Button(steamSession.isSyncing ? "同步中…" : "更新游戏库") { steamSession.refresh() }.disabled(steamSession.isSyncing)
                        Button("重新登录…") { store.mainWindow?.makeKeyAndOrderFront(nil); store.beginSteamLogin() }
                        Spacer()
                        Button("退出账号") { Task { await steamSession.logout() } }.disabled(steamSession.isSyncing)
                    }
                } else {
                    Button("登录 Steam") { store.mainWindow?.makeKeyAndOrderFront(nil); store.beginSteamLogin() }.controlSize(.large)
                }
                Text(steamSession.status).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Section("本机同步") {
                Text("在 Steam 官方页面登录，游戏库同步到这台 Mac。安装状态来自本地 Steam 清单；未安装的游戏在 Steam 中查看。")
                Text("会话由本应用的 WebKit 保存在本机，游戏数据保存在应用数据目录。无需搭建服务器或手动填写密钥。离线时使用上次同步的游戏库。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text("登录会话失效时重新登录。退出会清除此应用的会话与账号库缓存，并保留本地游戏和手动入口。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var general: some View {
        @Bindable var store = store
        return Form {
            Section("设置") {
                Button("重新打开初始设置…") { store.reopenSetup() }
                Button("还原初始设置…") { confirmingReset = true }
            }
            Section("外观") {
                Picker("外观模式", selection: $store.preferences.appearance) { ForEach(["深色", "浅色", "跟随系统"], id: \.self) { Text($0).tag($0) } }
                slider("游戏库海报大小", value: $store.preferences.posterWidth, range: 140...220, unit: "pt")
            }
            Section("启动") {
                Toggle("启动游戏后最小化窗口", isOn: $store.preferences.minimizeOnLaunch)
                Toggle("应用活跃时每分钟重新扫描", isOn: $store.preferences.automaticRescan)
            }
            Section("网络与原画") {
                Toggle("缺少本地原画时从 Steam CDN 补充", isOn: $store.preferences.onlineArtwork)
                Toggle("从 Steam 商店补充简介与平台信息", isOn: $store.preferences.onlineMetadata)
                Text("优先读取本地封面。补图与简介仅请求公开的 App ID 与游戏资源，无需登录或 API Key。关闭联网后仍可使用已缓存的资料。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("刷新游戏资料") { Task { await store.refreshMetadata() } }.disabled(store.isScanning)
            }
        }.formStyle(.grouped)
    }
    private var libraries: some View {
        Form {
            Section("Steam 目录") {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.preferences.steamRoot).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Text(store.steamFound ? "已找到 Steam · \(store.cachedPosterIDs.count) 张本地海报" : "尚未找到此目录").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("更换…") { store.chooseFolder(asSteamRoot: true) }
                }
            }
            Section("额外游戏库") {
                ForEach(store.preferences.additionalLibraries, id: \.self) { path in
                    HStack {
                        Text(path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        Button { store.preferences.additionalLibraries.removeAll { $0 == path }; Task { await store.scan() } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("移除此扫描位置")
                    }
                }
                Button("添加游戏库…") { store.chooseFolder(asSteamRoot: false) }
                Text("自动读取 libraryfolders.vdf 与 appmanifest_*.acf，支持外置硬盘；也可以直接选择 steamapps 文件夹。只读取文件，不修改 Steam 数据。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("扫描与管理") {
                HStack {
                    Text("\(store.games.filter(\.installed).count) 款已安装 · \(store.libraries.count) 个游戏库")
                    Spacer()
                    Button(store.isScanning ? "正在扫描…" : "重新扫描") { Task { await store.scan() } }.disabled(store.isScanning)
                }
                if let date = store.lastScan { Text("上次扫描：\(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(.secondary) }
                Button("恢复已移除的入口…") { store.mainWindow?.makeKeyAndOrderFront(nil); store.showingRemoved = true }
                ForEach(store.warnings, id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(.orange) }
                Text("时长与最近游玩来自最近更新的 Steam 本地活动文件。缺失的数据会标记为未知；不代表完整账号游戏库。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var privacy: some View {
        Form {
            Section("隐藏的游戏") {
                HStack {
                    Text("隐藏分类")
                    Spacer()
                    Button("显示") {
                        store.navigate(.library); store.selectFilter(.hidden)
                        store.mainWindow?.makeKeyAndOrderFront(nil); store.requestHiddenDisplay()
                    }
                }
                Text("隐藏的入口不会出现在主页、搜索、收藏、菜单栏或海报墙中。在隐藏分类里取消隐藏即可恢复。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("访问密码") {
                LabeledContent("密码保护", value: store.saved.hiddenPassword == nil ? "未启用" : "已启用")
                Button(store.saved.hiddenPassword == nil ? "设置密码…" : "修改或关闭密码…") { showingPassword = true }
                Text("只保存带随机盐的密码校验值。此功能控制本应用中的显示，不修改 Steam 游戏文件。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var wall: some View {
        @Bindable var store = store
        return Form {
            Section {
                ZStack(alignment: .bottomTrailing) {
                    WallCanvasView(preview: true)
                    Button("预览海报墙") { store.startWall() }.buttonStyle(.bordered).padding(12)
                }.frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 20).padding(.top, 15)
            }
            Section("待机") {
                Toggle("闲置后进入海报墙", isOn: $store.preferences.idleEnabled)
                Picker("等待时间", selection: $store.preferences.idleMinutes) {
                    ForEach([1.0, 2, 5, 10, 15, 30], id: \.self) { Text("\(Int($0)) 分钟").tag($0) }
                }.disabled(!store.preferences.idleEnabled)
                Toggle("海报墙进入全屏", isOn: $store.preferences.wallFullscreen)
                Toggle("显示时间与日期", isOn: $store.preferences.wallClock)
                Text("仅在本应用处于前台且没有弹窗时自动待机。自动待机时移动鼠标或按任意键返回；手动预览按 Esc 返回。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("海报与运动") {
                Picker("海报来源", selection: $store.preferences.wallSource) { ForEach(WallSource.allCases) { Text($0.rawValue).tag($0) } }
                Text("Steam 缓存可能含有商店浏览留下的海报，不代表已拥有。最多同时加载 240 张，以控制内存。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("滚动方式", selection: $store.preferences.wallDirection) { ForEach(WallDirection.allCases) { Text($0.rawValue).tag($0) } }
                slider("滚动速度", value: $store.preferences.wallSpeed, range: 8...80, unit: "pt/s")
                slider("海报大小", value: $store.preferences.wallPosterWidth, range: 130...320, unit: "pt")
                slider("海报间距", value: $store.preferences.wallGap, range: 4...32, unit: "pt")
                if store.preferences.wallDirection == .diagonal { slider("倾斜角度", value: $store.preferences.wallAngle, range: -25...25, unit: "°") }
                slider("亮度", value: $store.preferences.wallBrightness, range: 0.3...1, unit: "", scale: 100)
                Toggle("相邻行 / 列反向滚动", isOn: $store.preferences.wallAlternating)
                Toggle("反转滚动方向", isOn: $store.preferences.wallReverse)
                Text("系统开启“减弱动态效果”时海报墙保持静止。应用失去活跃状态时暂停绘制。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var about: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller.fill").font(.system(size: 54, weight: .light))
            Text("Steam Game Launcher").font(.system(size: 24, weight: .semibold)).tracking(-0.5)
            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("你的游戏，一个安静的入口。").font(.system(size: 16, weight: .medium))
            Text("原生 SwiftUI · 本地优先 · 可选 Steam 同步\n游戏启动、商店、社区与成就页面由 Steam 客户端处理。")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Divider().frame(width: 300)
            VStack(spacing: 10) {
                Link("GitHub", destination: URL(string: "https://github.com/lopleec/Steam-Game-Launcher")!)
                Link("版本与下载", destination: URL(string: "https://github.com/lopleec/Steam-Game-Launcher/releases")!)
                Link("MIT License", destination: URL(string: "https://github.com/lopleec/Steam-Game-Launcher/blob/main/LICENSE")!)
            }.font(.system(size: 11))
            Text("独立应用，与 Valve、Apple、Sony 无关联。游戏原画归各自权利人所有。")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            Button("在 Finder 中查看应用数据") { NSWorkspace.shared.open(AppFiles.directory) }.controlSize(.small)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, scale: Double = 1) -> some View {
        HStack(spacing: 15) {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue * scale))\(unit)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
        }
    }
}
