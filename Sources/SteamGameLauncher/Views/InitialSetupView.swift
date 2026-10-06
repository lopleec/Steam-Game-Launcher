import SwiftUI
import AppKit

/// A local draft keeps unfinished setup from changing the user's current preferences.
struct InitialSetupView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(SteamAccountSession.self) private var steamSession
    @State var preferences: Preferences
    @State private var step = 0
    @State private var scanResult: ScanResult?
    @State private var checking = false
    private let titles = ["游戏库", "Steam 账号", "外观与待机"]
    private let icons = ["externaldrive", "person.crop.circle", "rectangle.stack"]

    var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("欢迎使用").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text("让你的游戏，各就其位。").font(.system(size: 30, weight: .semibold)).tracking(-0.8)
                    Text("几步设置，开始你的下一段旅程。之后随时可以调整。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(step + 1) / 3").font(.system(size: 12, design: .monospaced)).foregroundStyle(.tertiary).padding(.top, 8)
            }
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(titles.indices, id: \.self) { index in
                        Button { step = index } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icons[index]).font(.system(size: 15)).frame(width: 22)
                                Text(titles[index]).font(.system(size: 13, weight: step == index ? .semibold : .medium))
                                Spacer(minLength: 0)
                                if index < step { Image(systemName: "checkmark").font(.system(size: 10)) }
                            }.foregroundStyle(step == index ? .primary : .secondary)
                                .padding(14).background(step == index ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Label("设置保存在这台 Mac", systemImage: "lock.shield")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }.frame(width: 185)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if step == 0 { libraryStep }
                        else if step == 1 { accountStep }
                        else { appearanceStep }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 4)
                }.scrollIndicators(.hidden)
            }.frame(minHeight: 280, maxHeight: 400)
            Divider()
            HStack {
                Button { finish() } label: {
                    Text("稍后设置").padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                if step > 0 { Button("上一步") { step -= 1 }.controlSize(.large) }
                Button(step == 2 ? "进入游戏库" : "下一步") {
                    if step == 2 { finish() } else { step += 1 }
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
        }.padding(32).frame(maxWidth: 940, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: preferences.steamRoot + "|" + preferences.additionalLibraries.joined(separator: "|")) {
                checking = true; scanResult = nil
                let root = preferences.steamRoot, extra = preferences.additionalLibraries
                let result = await Task.detached { SteamScanner().scan(root: root, additionalLibraries: extra) }.value
                guard !Task.isCancelled else { return }
                scanResult = result; checking = false
            }
    }
    private var libraryStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("连接本机游戏库", subtitle: "自动查找 Steam 已安装的游戏，也支持外置硬盘。")
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(checking ? "正在查找…" : scanResult?.steamFound == true ? "已找到 Steam" : "选择 Steam 目录", systemImage: "externaldrive")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("更换目录…") { chooseFolder(root: true) }
                }
                Text(preferences.steamRoot).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                if let result = scanResult {
                    Text("\(result.games.filter(\.installed).count) 款已安装游戏 · \(result.libraries.count) 个游戏库")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            ForEach(preferences.additionalLibraries, id: \.self) { path in
                HStack {
                    Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "externaldrive.badge.plus").font(.system(size: 12))
                    Spacer()
                    Button { preferences.additionalLibraries.removeAll { $0 == path } } label: {
                        Image(systemName: "minus.circle").frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("移除此扫描位置")
                }
            }
            Button("添加其他游戏库…", systemImage: "plus") { chooseFolder(root: false) }
            Text("还没有安装游戏也可以继续，稍后从 Steam 游戏库添加。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("把 Steam 游戏库带过来", subtitle: "登录后查看账号内的游戏，并标记这台 Mac 上已安装的游戏。")
            if let account = store.saved.steamAccount {
                Label("已连接 \(account.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                Text("已同步 \(account.games.count) 款游戏").font(.system(size: 13)).foregroundStyle(.secondary)
                Button("更新游戏库") { steamSession.refresh() }.disabled(steamSession.isSyncing)
            } else {
                Button("登录 Steam", systemImage: "arrow.up.right") { store.beginSteamLogin() }
                    .controlSize(.large).buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("在 Steam 官方页面完成登录", systemImage: "checkmark.shield")
                Label("登录会话和游戏数据保存在本机", systemImage: "internaldrive")
                Label("无需填写 API 密钥，可随时更新游戏库", systemImage: "arrow.clockwise")
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8)
            Text("这一步可以跳过，仅使用本机游戏库。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var appearanceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("按你的习惯开始", subtitle: "选择外观和待机方式，更多细节可在设置中调整。")
            HStack {
                Text("外观").font(.system(size: 13)).frame(width: 100, alignment: .leading)
                Picker("外观", selection: $preferences.appearance) {
                    ForEach(["深色", "浅色", "跟随系统"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            Toggle("缺少封面时自动补充 Steam 原画", isOn: $preferences.onlineArtwork)
            Toggle("补充游戏简介与平台信息", isOn: $preferences.onlineMetadata)
            Divider()
            Toggle("闲置时显示海报墙", isOn: $preferences.idleEnabled)
            HStack {
                Picker("等待时间", selection: $preferences.idleMinutes) {
                    ForEach([1.0, 2, 5, 10, 15, 30], id: \.self) { Text("\(Int($0)) 分钟").tag($0) }
                }
                Picker("滚动方式", selection: $preferences.wallDirection) {
                    ForEach(WallDirection.allCases) { Text($0.rawValue).tag($0) }
                }
            }.disabled(!preferences.idleEnabled)
            Toggle("启动游戏后最小化窗口", isOn: $preferences.minimizeOnLaunch)
        }.font(.system(size: 13))
    }
    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 20, weight: .semibold)).tracking(-0.4)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }
    }
    private func chooseFolder(root: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = root ? "选择 Steam 目录" : "选择其他 Steam 游戏库或 steamapps 文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if root { preferences.steamRoot = url.path }
        else if !preferences.additionalLibraries.contains(url.path) { preferences.additionalLibraries.append(url.path) }
    }
    private func finish() { store.finishSetup(preferences); store.navigate(.home) }
}
