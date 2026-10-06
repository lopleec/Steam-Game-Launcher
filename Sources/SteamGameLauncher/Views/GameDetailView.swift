import SwiftUI

struct GameDetailView: View {
    let gameID: String
    @Environment(LibraryStore.self) private var store
    @State private var ambient = Color(red: 0.13, green: 0.17, blue: 0.17)
    @State private var logo: NSImage?
    private var game: Game? { store.games.first { $0.id == gameID } }
    var body: some View {
        if let game {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    ambient.opacity(0.6)
                    GameArtwork(game: game, kind: .hero).frame(height: geometry.size.height * 0.88)
                        .overlay(LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.12), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                        .overlay(LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .leading, endPoint: .trailing))
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0.65), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer().frame(height: max(geometry.size.height * 0.2, 160))
                            HStack(alignment: .bottom, spacing: 50) {
                                VStack(alignment: .leading, spacing: 20) {
                                    Label(game.entryLabel, systemImage: game.isSteam ? (game.installed ? "checkmark.circle" : "link") : "app")
                                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                                    if let logo {
                                        Image(nsImage: logo).resizable().scaledToFit().frame(maxWidth: min(geometry.size.width * 0.45, 410), maxHeight: 135, alignment: .leading)
                                            .shadow(color: .black.opacity(0.5), radius: 12, y: 3).accessibilityLabel(game.name)
                                    } else {
                                        Text(game.name).font(.system(size: 54, weight: .bold, design: .default)).tracking(-1.4).lineLimit(3)
                                    }
                                    Text((game.metadata?.genres.prefix(4).joined(separator: "  ·  ") ?? (game.isSteam ? "Steam 游戏" : "本地入口")) + "  ·  " + game.platformLabel)
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.66))
                                    if let summary = game.metadata?.summary, !summary.isEmpty {
                                        Text(summary).font(.system(size: 14)).foregroundStyle(.white.opacity(0.75)).lineSpacing(5).lineLimit(3).frame(maxWidth: 540, alignment: .leading)
                                    }
                                    HStack(spacing: 12) {
                                        PlayButton(game: game)
                                        RoundButton(icon: store.saved.favorites.contains(game.id) ? "heart.fill" : "heart", label: "收藏") { store.toggleFavorite(game) }
                                        Menu { GameContextMenu(game: game) } label: {
                                            Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 38, height: 38).background(.white.opacity(0.09), in: Circle())
                                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 38)
                                    }.padding(.top, 8)
                                    Text(game.lastPlayedLabel).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if geometry.size.width > 1080 {
                                    GameArtwork(game: game).frame(width: 180, height: 270).clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.16)))
                                        .shadow(color: .black.opacity(0.4), radius: 12, y: 8).padding(.trailing, 18)
                                }
                            }.padding(.top, 20).padding(.bottom, 52)
                            Divider().overlay(.white.opacity(0.12))
                            HStack(alignment: .top, spacing: 45) {
                                fact("游玩时长", value: game.playtimeLabel, icon: "clock")
                                fact("安装大小", value: game.sizeOnDisk > 0 ? ByteCountFormatter.string(fromByteCount: game.sizeOnDisk, countStyle: .file) : "未知", icon: "internaldrive")
                                fact("平台", value: game.platformLabel, icon: "desktopcomputer")
                                if game.isSteam { fact("STEAM APP ID", value: game.id, icon: "number") }
                                else { fact("文件类型", value: game.localTarget?.kind.label ?? "本地文件", icon: "doc") }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 28)
                            Divider().overlay(.white.opacity(0.08))
                            VStack(alignment: .leading, spacing: 20) {
                                Text(game.isSteam ? "探索这款游戏" : "本地入口").font(.system(size: 19, weight: .semibold))
                                if game.isSteam {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                                    ForEach([SteamLink.GameAction.store, .community, .achievements, .guides, .discussions, .workshop, .news, .library]) { action in
                                        Button { store.action(action, game: game) } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: action.icon).font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                                                Text(action.rawValue).font(.system(size: 12, weight: .medium))
                                                Spacer(minLength: 0)
                                                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                                            }.padding(15).frame(minHeight: 48).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                    }
                                }
                                if game.metadata?.mac == false {
                                    Label("商店未标记 macOS 支持；启动和兼容性由 Steam 与游戏决定。", systemImage: "info.circle")
                                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                                }
                                if game.metadata == nil { Text("离线时使用本地清单；平台与简介将在联网后补充。").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)) }
                                if let developers = game.metadata?.developers, !developers.isEmpty {
                                    Text("开发者  ·  " + developers.joined(separator: " / ")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                                }
                                } else {
                                    Text(game.localTarget?.path ?? "").font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.65)).textSelection(.enabled)
                                    HStack(spacing: 12) {
                                        localAction("在 Finder 中显示", icon: "folder") { store.reveal(game) }
                                        localAction("启动参数", icon: "terminal") { store.editingLocalGame = game }
                                        if game.localTarget?.kind != .application {
                                            localAction("运行日志", icon: "doc.text") { store.showLocalLog(game) }
                                        }
                                    }
                                }
                            }.padding(.top, 30).padding(.bottom, 45)
                        }.padding(.horizontal, 48)
                    }.scrollIndicators(.hidden)
                }.background(.black).foregroundStyle(.white).clipped()
            }
            .task(id: gameID) { await store.loadMetadata(for: gameID) }
            .task(id: "\(gameID)|\(store.artworkRevision)|\(store.preferences.steamRoot)") {
                logo = nil
                let image = await ImageCache.shared.image(for: game, kind: .hero, store: store)
                if !Task.isCancelled, let image, let color = image.averageColor { ambient = Color(nsColor: color) }
                let loadedLogo = await ImageCache.shared.image(for: game, kind: .logo, store: store)
                if !Task.isCancelled { logo = loadedLogo }
            }
        }
    }
    private func localAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium)).padding(.horizontal, 18).frame(height: 48)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func fact(_ label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(label, systemImage: icon).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            Text(value).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.9))
        }
    }
}

extension NSImage {
    var averageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return NSColor(red: CGFloat(bytes[0]) / 255, green: CGFloat(bytes[1]) / 255, blue: CGFloat(bytes[2]) / 255, alpha: 1)
    }
}
