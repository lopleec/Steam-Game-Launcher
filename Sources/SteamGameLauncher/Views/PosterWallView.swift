import SwiftUI

struct PosterWallView: View {
    @Environment(LibraryStore.self) private var store
    @State private var controlsVisible = true
    @State private var controlsTask: Task<Void, Never>?
    var body: some View {
        ZStack {
            WallCanvasView().ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            if store.preferences.wallClock {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.date, format: .dateTime.hour().minute()).font(.system(size: 58, weight: .light, design: .default)).monospacedDigit().tracking(-1.5)
                        Text(context.date, format: .dateTime.weekday(.wide).month().day()).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    }
                }.foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 10, y: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(48).allowsHitTesting(false)
            }
            VStack {
                HStack(spacing: 15) {
                    Text("Steam Game Launcher").tracking(-0.15).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Menu {
                        ForEach(WallDirection.allCases) { direction in Button(direction.rawValue) { store.preferences.wallDirection = direction } }
                    } label: { Label(store.preferences.wallDirection.rawValue, systemImage: "arrow.up.right").font(.system(size: 12)) }
                        .menuStyle(.borderlessButton).fixedSize()
                    SettingsLink { Image(systemName: "slider.horizontal.3").frame(width: 40, height: 40).contentShape(Rectangle()) }.buttonStyle(.plain).help("海报墙设置")
                    Button { store.showingWall = false } label: {
                        Label("返回", systemImage: "xmark").font(.system(size: 12, weight: .medium)).padding(.horizontal, 15).frame(height: 33).background(.ultraThinMaterial, in: Capsule()).contentShape(Capsule())
                    }.buttonStyle(.plain).keyboardShortcut(.escape, modifiers: [])
                }.padding(.horizontal, 40).padding(.top, 25)
                Spacer()
                HStack { Spacer(); Text(store.automaticWall ? "移动鼠标或按任意键返回" : "按 Esc 返回游戏库").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)) }.padding(40)
            }.foregroundStyle(.white).opacity(controlsVisible ? 1 : 0)
        }.background(.black)
        .onAppear { showControls() }
        .onContinuousHover { phase in if case .active = phase { showControls() } }
        .onDisappear { controlsTask?.cancel() }
    }
    private func showControls() {
        controlsVisible = true; controlsTask?.cancel()
        controlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.6)) { controlsVisible = false } }
        }
    }
}

struct WallCanvasView: View {
    var preview = false
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var images: [String: NSImage] = [:]
    @State private var start = Date()
    @State private var pausedAt: Date?
    private var games: [Game] { Array(store.wallGames.prefix(240)) }
    private var loadID: String {
        store.preferences.steamRoot + "|" + games.map(\.id).joined(separator: ",") + "|\(store.saved.customArtwork)|\(store.artworkRevision)|\(store.preferences.onlineArtwork)"
    }
    var body: some View {
        let drawnGames = games
        TimelineView(.animation(minimumInterval: preview ? 1 / 15 : 1 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            Canvas(opaque: true, rendersAsynchronously: true) { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let diagonal = store.preferences.wallDirection == .diagonal
                let extent = diagonal ? hypot(size.width, size.height) : 0
                let boardSize = diagonal ? CGSize(width: extent, height: extent) : size
                if diagonal {
                    context.translateBy(x: size.width / 2, y: size.height / 2)
                    context.rotate(by: .degrees(store.preferences.wallAngle))
                    context.translateBy(x: -extent / 2, y: -extent / 2)
                }
                let width = preview ? store.preferences.wallPosterWidth * 0.42 : store.preferences.wallPosterWidth
                let gap = preview ? store.preferences.wallGap * 0.42 : store.preferences.wallGap
                let elapsed = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
                let tiles = WallLayout.tiles(size: boardSize, width: width, gap: gap, elapsed: elapsed,
                                             speed: store.preferences.wallSpeed * (preview ? 0.42 : 1),
                                             vertical: store.preferences.wallDirection == .vertical,
                                             alternating: store.preferences.wallAlternating,
                                             reverse: store.preferences.wallReverse, gameCount: drawnGames.count)
                for tile in tiles {
                    let game = drawnGames[tile.gameIndex]
                    let clip = Path(roundedRect: tile.rect, cornerRadius: preview ? 5 : 10)
                    if let image = images[game.id] {
                        var drawing = context
                        drawing.clip(to: clip)
                        drawing.opacity = store.preferences.wallBrightness
                        let ratio = max(tile.rect.width / image.size.width, tile.rect.height / image.size.height)
                        let rect = CGRect(x: tile.rect.midX - image.size.width * ratio / 2, y: tile.rect.midY - image.size.height * ratio / 2,
                                          width: image.size.width * ratio, height: image.size.height * ratio)
                        drawing.draw(Image(nsImage: image), in: rect)
                    } else {
                        context.fill(clip, with: .color(Color(white: 0.12)))
                        let text = Text(game.name).font(.system(size: preview ? 10 : 17, weight: .medium)).foregroundColor(.white.opacity(0.4))
                        context.draw(text, at: CGPoint(x: tile.rect.midX, y: tile.rect.midY))
                    }
                    context.stroke(clip, with: .color(.white.opacity(0.08)), lineWidth: 0.7)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && pausedAt == nil { pausedAt = Date() }
            else if phase == .active, let pausedAt { start = start.addingTimeInterval(Date().timeIntervalSince(pausedAt)); self.pausedAt = nil }
        }
        .task(id: loadID) {
            images = [:]; start = Date()
            let games = games
            await withTaskGroup(of: (String, NSImage?).self) { group in
                var iterator = games.makeIterator()
                for _ in 0..<8 {
                    if let game = iterator.next() { group.addTask { @MainActor in (game.id, await ImageCache.shared.image(for: game, kind: .poster, store: store)) } }
                }
                for await (id, image) in group {
                    guard !Task.isCancelled else { group.cancelAll(); break }
                    if let image { images[id] = image }
                    if let game = iterator.next() { group.addTask { @MainActor in (game.id, await ImageCache.shared.image(for: game, kind: .poster, store: store)) } }
                }
            }
        }
        .accessibilityLabel("\(store.preferences.wallDirection.rawValue)滚动的游戏海报墙")
    }
}
