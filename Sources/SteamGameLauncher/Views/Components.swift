import SwiftUI

enum Palette {
    static let windowColor = NSColor(name: NSColor.Name("Steam Game LauncherBackground")) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.045, green: 0.05, blue: 0.055, alpha: 1)
            : NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.97, alpha: 1)
    }
    static let background = Color(nsColor: windowColor)
    static let accent = Color(red: 0.75, green: 0.9, blue: 0.81)
}

struct RoundButton: View {
    var icon: String
    var label: String
    var action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium)).frame(width: 40, height: 40)
                .background(hovered ? Color.primary.opacity(0.13) : Color.primary.opacity(0.055), in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08))).contentShape(Circle())
        }.buttonStyle(.plain).onHover { hovered = $0 }.help(label).accessibilityLabel(label)
    }
}
struct PlayButton: View {
    let game: Game
    var compact = false
    @Environment(LibraryStore.self) private var store
    var body: some View {
        Button { store.launch(game) } label: {
            HStack(spacing: 10) {
                Image(systemName: game.installed ? "play.fill" : "arrow.up.right").font(.system(size: compact ? 13 : 15, weight: .semibold))
                Text(game.launchLabel).font(.system(size: compact ? 13 : 15, weight: .semibold))
            }
            .foregroundStyle(.black).padding(.horizontal, compact ? 17 : 27).frame(height: compact ? 39 : 48)
            .background(.white, in: Capsule()).contentShape(Capsule())
        }.buttonStyle(.plain)
        .help(game.isSteam ? (game.installed ? "通过 Steam 启动 \(game.name)" : "打开 Steam 详情") : "打开本地文件")
    }
}

struct GameContextMenu: View {
    let game: Game
    @Environment(LibraryStore.self) private var store
    var body: some View {
        Button(game.launchLabel, systemImage: game.installed ? "play.fill" : "arrow.up.right") { store.launch(game) }
        Button("游戏详情", systemImage: "info.circle") { store.selectedGame = game }
        Button(store.saved.favorites.contains(game.id) ? "取消收藏" : "加入收藏", systemImage: "heart") { store.toggleFavorite(game) }
        if !store.saved.collections.isEmpty {
            Menu("添加到合集") {
                ForEach(store.saved.collections) { collection in
                    Button { store.toggleCollection(game, collection: collection) } label: {
                        Label(collection.name, systemImage: collection.gameIDs.contains(game.id) ? "checkmark" : "plus")
                    }
                }
            }
        }
        Divider()
        if game.isSteam {
            ForEach(SteamLink.GameAction.allCases.filter { $0 != .play }) { action in
                Button(action.rawValue, systemImage: action.icon) { store.action(action, game: game) }
            }
        } else {
            Button("启动参数…", systemImage: "terminal") { store.editingLocalGame = game }
            if game.localTarget?.kind != .application { Button("查看运行日志") { store.showLocalLog(game) } }
        }
        Divider()
        Button(game.isSteam ? "复制启动链接" : "复制文件链接", systemImage: "link") { store.copyLaunchLink(game) }
        if game.installPath != nil { Button("在 Finder 中显示", systemImage: "folder") { store.reveal(game) } }
        Menu("自定义原画") {
            Button("更换海报…") { store.chooseArtwork(game, kind: .poster) }
            Button("更换背景…") { store.chooseArtwork(game, kind: .hero) }
            Button(game.isSteam ? "恢复 Steam 原画" : "恢复默认图标") {
                store.saved.customArtwork.removeValue(forKey: "\(game.id)_poster")
                store.saved.customArtwork.removeValue(forKey: "\(game.id)_hero")
                ImageCache.shared.clear(); store.artworkRevision += 1
            }
        }
        Divider()
        if store.saved.hidden.contains(game.id) {
            Button("取消隐藏", systemImage: "eye") { store.unhide(game) }
        } else { Button("隐藏此游戏", systemImage: "eye.slash") { store.hide(game) } }
        if game.addedManually { Button("移除快捷入口", systemImage: "minus.circle") { store.removeManual(game) } }
    }
}

struct PosterCard: View {
    let game: Game
    var width: CGFloat = 172
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack(alignment: .bottom) {
                Button { store.selectedGame = game } label: {
                    GameArtwork(game: game).frame(width: width, height: width * 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(hovered || focused ? 0.85 : 0.08), lineWidth: hovered || focused ? 2 : 1))
                }.buttonStyle(.plain).focused($focused).accessibilityLabel("\(game.name)，查看详情")
                    .help("\(game.name) · \(game.platformLabel)")
                if hovered || focused {
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 95).clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)).allowsHitTesting(false)
                    HStack {
                        Button { store.launch(game) } label: {
                            Image(systemName: game.installed ? "play.fill" : "arrow.up.right")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.black)
                                .frame(width: 40, height: 40).background(.white, in: Circle())
                        }.buttonStyle(.plain).help(game.installed ? "启动游戏" : "在 Steam 中查看")
                        Spacer()
                        Button { store.toggleFavorite(game) } label: {
                            Image(systemName: store.saved.favorites.contains(game.id) ? "heart.fill" : "heart")
                                .font(.system(size: 17)).foregroundStyle(.white).frame(width: 40, height: 40).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("收藏")
                    }.padding(13)
                }
            }
            .overlay(alignment: .topLeading) {
                if !game.nonMacPlatforms.isEmpty {
                    HStack(spacing: 7) {
                        ForEach(game.nonMacPlatforms) { platform in
                            PlatformMark(platform: platform).frame(width: 16, height: 16)
                        }
                    }
                    .foregroundStyle(Color(white: 0.78)).padding(7)
                    .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 6))
                    .padding(9).allowsHitTesting(false)
                    .accessibilityLabel("支持平台：" + game.nonMacPlatforms.map(\.rawValue).joined(separator: "、"))
                }
            }
            .scaleEffect(hovered && !reduceMotion ? 1.025 : 1)
            .shadow(color: .black.opacity(hovered ? 0.25 : 0), radius: hovered ? 8 : 0, y: 4)
            Button { store.selectedGame = game } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(game.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if game.installed { Circle().fill(Palette.accent).frame(width: 4, height: 4) }
                    Text(game.playtimeMinutes == nil ? (game.isSteam ? (game.installed ? "已安装" : game.owned == true ? "在库里" : "快捷入口") : game.entryLabel) : game.playtimeLabel)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if store.saved.favorites.contains(game.id) { Spacer(minLength: 0); Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
            }.padding(.horizontal, 1).frame(width: width, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.frame(width: width)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: hovered)
        .contextMenu { GameContextMenu(game: game) }
        .onKeyPress(.return) { store.launch(game); return .handled }
    }
}

struct SectionTitle: View {
    var title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 22, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) { HStack(spacing: 7) { Text(actionTitle); Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)) }.font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle()) }.buttonStyle(.plain)
            }
        }
    }
}

struct GameShelf: View {
    var title: String
    var subtitle: String? = nil
    var games: [Game]
    @Environment(LibraryStore.self) private var store
    var body: some View {
        VStack(spacing: 20) {
            SectionTitle(title: title, subtitle: subtitle, actionTitle: "查看全部") { store.navigate(.library) }.padding(.horizontal, 42)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(games) { game in PosterCard(game: game, width: store.preferences.posterWidth) }
                }.padding(.horizontal, 42).padding(.top, 7).padding(.bottom, 18)
            }.scrollIndicators(.hidden)
        }
    }
}

private struct PlatformMark: View {
    let platform: GamePlatform
    var body: some View {
        if platform == .windows {
            VStack(spacing: 2) {
                HStack(spacing: 2) { Rectangle(); Rectangle() }
                HStack(spacing: 2) { Rectangle(); Rectangle() }
            }
        } else {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                ZStack {
                    Ellipse().frame(width: w * 0.8, height: h * 0.65).offset(y: h * 0.15)
                    Capsule().frame(width: w * 0.6, height: h * 0.9)
                    Ellipse().fill(.black.opacity(0.55)).frame(width: w * 0.35, height: h * 0.5).offset(y: h * 0.15)
                    HStack(spacing: w * 0.1) {
                        Circle().fill(.black.opacity(0.8)).frame(width: w * 0.12)
                        Circle().fill(.black.opacity(0.8)).frame(width: w * 0.12)
                    }.frame(height: h * 0.12).offset(y: -h * 0.26)
                    Ellipse().fill(.black.opacity(0.65)).frame(width: w * 0.25, height: h * 0.12).offset(y: -h * 0.12)
                    HStack(spacing: w * 0.15) { Capsule(); Capsule() }
                        .frame(width: w * 0.85, height: h * 0.16).offset(y: h * 0.43)
                }.frame(width: w, height: h)
            }
        }
    }
}
