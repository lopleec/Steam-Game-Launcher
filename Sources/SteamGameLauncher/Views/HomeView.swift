import SwiftUI

struct HomeView: View {
    var topInset: CGFloat = 0
    @Environment(LibraryStore.self) private var store
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(spacing: 34) {
                if let game = store.heroGame {
                    HeroView(game: game).frame(height: min(480, max(320, geometry.size.height - topInset - 435)) + topInset)
                    GameShelf(title: store.recentGames.isEmpty ? "准备开玩" : "最近游玩",
                              subtitle: "你的游戏，随时继续。",
                              games: Array((store.recentGames.isEmpty ? store.visibleGames : store.recentGames).prefix(12)))
                    if !store.favoriteGames.isEmpty {
                        GameShelf(title: "心头好", games: store.favoriteGames)
                    }
                    if !store.saved.collections.isEmpty { collections }
                    footer
                } else {
                    EmptyLibraryView().frame(minHeight: 540).padding(.top, topInset)
                }
            }.padding(.bottom, 28).background(ScrollBoundary())
        }.scrollIndicators(.hidden)
        }
    }
    private var collections: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: "你的合集", actionTitle: "管理合集") { store.showingCollections = true }
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(store.saved.collections) { collection in
                        Button {
                            store.navigate(.library); store.collectionID = collection.id
                        } label: {
                            HStack {
                                Image(systemName: "square.stack.3d.up").font(.system(size: 23, weight: .light))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(collection.name).font(.system(size: 15, weight: .medium))
                                    Text("\(collection.gameIDs.count) 款游戏").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                            }.padding(20).frame(width: 260).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden)
        }.padding(.horizontal, 42)
    }
    private var footer: some View {
        HStack {
            Label("\(store.visibleGames.filter(\.installed).count) 款游戏已就绪", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button { store.startWall() } label: { Label("让游戏成为风景", systemImage: "rectangle.stack").font(.system(size: 12)).foregroundStyle(.secondary).padding(10).contentShape(Rectangle()) }.buttonStyle(.plain)
        }.padding(.horizontal, 42).padding(.top, 2)
    }
}

struct HeroView: View {
    let game: Game
    @Environment(LibraryStore.self) private var store
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                GameArtwork(game: game, kind: .hero)
                LinearGradient(stops: [.init(color: .black.opacity(0.6), location: 0), .init(color: .black.opacity(0.12), location: 0.7), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [.init(color: .clear, location: 0.38), .init(color: Palette.background.opacity(0.45), location: 0.67), .init(color: Palette.background, location: 1)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 17) {
                    Label(store.activityDate(game) == nil ? "从这里开始" : "继续你的旅程", systemImage: "play.circle")
                        .font(.system(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(.white.opacity(0.75))
                    Text(game.name).font(.system(size: min(geometry.size.width * 0.043, 55), weight: .bold, design: .default))
                        .tracking(-1.5).foregroundStyle(.white).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: min(geometry.size.width * 0.62, 650), alignment: .leading)
                    HStack(spacing: 12) {
                        if let genres = game.metadata?.genres, !genres.isEmpty { Text(genres.prefix(3).joined(separator: " · ")) }
                        else { Text(game.entryLabel) }
                        if game.playtimeMinutes != nil { Text("·"); Text(game.playtimeLabel) }
                    }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 12) {
                        PlayButton(game: game)
                        Button { store.selectedGame = game } label: {
                            Text("游戏详情").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                                .padding(.horizontal, 23).frame(height: 48).background(.white.opacity(0.12), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.12))).contentShape(Capsule())
                        }.buttonStyle(.plain)
                        Menu { GameContextMenu(game: game) } label: {
                            Image(systemName: "ellipsis").font(.system(size: 19)).foregroundStyle(.white).frame(width: 46, height: 46)
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 46).help("更多操作")
                    }.padding(.top, 5)
                }.padding(.leading, 44).padding(.bottom, 41)
                HStack(spacing: 7) {
                    ForEach(Array((store.recentGames.isEmpty ? store.visibleGames : store.recentGames).prefix(6))) { item in
                        Button { withAnimation(.easeInOut(duration: 0.3)) { store.heroID = item.id } } label: {
                            Capsule().fill(.white.opacity(game.id == item.id ? 0.9 : 0.3)).frame(width: game.id == item.id ? 22 : 6, height: 6).frame(minWidth: 22, minHeight: 30).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(item.name).accessibilityLabel("展示 \(item.name)")
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.trailing, 44).padding(.bottom, 54)
            }.clipped()
        }.id(game.id)
    }
}

struct EmptyLibraryView: View {
    @Environment(LibraryStore.self) private var store
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller").font(.system(size: 62, weight: .ultraLight)).foregroundStyle(.secondary)
            Text(store.isScanning ? "正在寻找你的游戏" : "你的下一段旅程，从这里开始").font(.system(size: 28, weight: .semibold))
            Text(store.steamFound ? "没有找到安装清单。添加其他 Steam 游戏库，或用 App ID 创建快捷入口。" : "自动读取 Steam 的本地游戏。也可以选择外置硬盘上的游戏库。")
                .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
            HStack(spacing: 14) {
                Button("选择 Steam 目录…") { store.chooseFolder(asSteamRoot: true) }.buttonStyle(.borderedProminent)
                Button("添加游戏库…") { store.chooseFolder(asSteamRoot: false) }.buttonStyle(.bordered)
                Button("使用 App ID…") { store.showingAddGame = true }.buttonStyle(.bordered)
            }
            if store.isScanning { ProgressView().controlSize(.small) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
