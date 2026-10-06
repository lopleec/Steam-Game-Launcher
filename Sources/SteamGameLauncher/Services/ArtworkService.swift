import AppKit
import SwiftUI
import ImageIO

actor ArtworkService {
    static let shared = ArtworkService()
    private var pending: [String: Task<Data?, Never>] = [:]

    func data(id: String, kind: ArtworkKind, root: String, customPath: String?, online: Bool) async -> Data? {
        let key = "\(root)|\(id)|\(kind.rawValue)|\(customPath ?? "")|\(online)"
        if let task = pending[key] { return await task.value }
        let task = Task<Data?, Never> {
            if let customPath, let data = try? Data(contentsOf: URL(fileURLWithPath: customPath)) { return data }
            let cache = URL(fileURLWithPath: root).appendingPathComponent("appcache/librarycache")
            for file in kind.filenames {
                for url in [cache.appendingPathComponent("\(id)/\(file)"), cache.appendingPathComponent("\(id)_\(file)")] {
                    if let data = try? Data(contentsOf: url), !data.isEmpty { return data }
                }
            }
            // New Steam clients also place artwork beneath content-hash subfolders.
            let appFolder = cache.appendingPathComponent(id)
            if let enumerator = FileManager.default.enumerator(at: appFolder, includingPropertiesForKeys: nil) {
                var matches = [URL]()
                while let file = enumerator.nextObject() as? URL {
                    if kind.filenames.contains(file.lastPathComponent) { matches.append(file) }
                }
                if let preferred = matches.sorted(by: { $0.path < $1.path }).first,
                   let data = try? Data(contentsOf: preferred) { return data }
            }
            let disk = AppFiles.directory.appendingPathComponent("Artwork/\(id)_\(kind.rawValue).cache")
            if let data = try? Data(contentsOf: disk) { return data }
            guard online, SteamLink.validAppID(id) else { return nil }
            var filenames = kind == .poster ? ["library_600x900_2x.jpg", "library_600x900.jpg"] : [kind.remoteFilename]
            if kind == .hero { filenames.append("header.jpg") }
            for file in filenames {
                guard !Task.isCancelled, let url = URL(string: "https://steamcdn-a.akamaihd.net/steam/apps/\(id)/\(file)") else { continue }
                var request = URLRequest(url: url); request.timeoutInterval = 8
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode == 200,
                   response.mimeType?.hasPrefix("image/") == true, data.count < 15_000_000 {
                    try? FileManager.default.createDirectory(at: disk.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: disk, options: .atomic)
                    return data
                }
            }
            return nil
        }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        return result
    }
}

struct DecodedArtwork: @unchecked Sendable {
    let image: CGImage
}

actor ArtworkDecoder {
    static let shared = ArtworkDecoder()
    func decode(_ data: Data, kind: ArtworkKind) -> DecodedArtwork? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: kind == .poster ? 480 : 1600,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return DecodedArtwork(image: thumbnail)
    }
}

@MainActor final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private var failures: [String: Date] = [:]
    private var pending: [String: Task<NSImage?, Never>] = [:]
    private var revision = 0
    init() { cache.totalCostLimit = 160 * 1024 * 1024; cache.countLimit = 600 }
    private func key(_ game: Game, _ kind: ArtworkKind, _ store: LibraryStore) -> String {
        "\(store.preferences.steamRoot)|\(game.id)|\(kind.rawValue)|\(store.saved.customArtwork["\(game.id)_\(kind.rawValue)"] ?? "")|\(store.preferences.onlineArtwork)"
    }
    func cached(for game: Game, kind: ArtworkKind, store: LibraryStore) -> NSImage? {
        cache.object(forKey: key(game, kind, store) as NSString)
    }
    func image(for game: Game, kind: ArtworkKind, store: LibraryStore) async -> NSImage? {
        let key = key(game, kind, store)
        if let image = cache.object(forKey: key as NSString) { return image }
        if let task = pending[key] { return await task.value }
        if let failure = failures[key], Date().timeIntervalSince(failure) < 60 { return nil }
        let custom = store.saved.customArtwork["\(game.id)_\(kind.rawValue)"]
        let root = store.preferences.steamRoot, online = store.preferences.onlineArtwork, generation = revision
        let task = Task<NSImage?, Never> {
            if let target = game.localTarget, custom == nil {
                return kind == .poster ? NSWorkspace.shared.icon(forFile: target.path) : nil
            }
            guard let data = await ArtworkService.shared.data(id: game.id, kind: kind, root: root, customPath: custom, online: online),
                  let decoded = await ArtworkDecoder.shared.decode(data, kind: kind) else { return nil }
            let cg = decoded.image
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        pending[key] = task
        let result = await task.value
        guard generation == revision else { return result }
        pending[key] = nil
        if let result { cache.setObject(result, forKey: key as NSString, cost: Int(result.size.width * result.size.height * 4)) }
        else { failures[key] = Date() }
        return result
    }
    func clear() { revision += 1; cache.removeAllObjects(); failures.removeAll(); pending.removeAll() }
}

struct GameArtwork: View {
    let game: Game
    var kind: ArtworkKind = .poster
    var contentMode: ContentMode = .fill
    @Environment(LibraryStore.self) private var store
    @State private var artwork: NSImage?
    private var requestID: String {
        "\(game.id)|\(kind.rawValue)|\(store.preferences.steamRoot)|\(store.preferences.onlineArtwork)|\(store.artworkRevision)|\(store.saved.customArtwork["\(game.id)_\(kind.rawValue)"] ?? "")"
    }
    var body: some View {
        GeometryReader { geometry in
            if let artwork {
                if !game.isSteam && kind == .poster && store.saved.customArtwork["\(game.id)_poster"] == nil {
                    ZStack {
                        LinearGradient(colors: [.init(white: 0.18), .init(white: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(nsImage: artwork).resizable().scaledToFit().frame(width: geometry.size.width * 0.58, height: geometry.size.width * 0.58)
                    }
                } else {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            } else if kind != .logo {
                ZStack {
                    LinearGradient(colors: [.init(white: 0.19), .init(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 14) {
                        Image(systemName: "gamecontroller").font(.system(size: kind == .hero ? 42 : 28, weight: .ultraLight))
                        if kind == .poster { Text(game.name).font(.system(size: 19, weight: .semibold)).multilineTextAlignment(.center).padding(.horizontal, 14) }
                    }.foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .task(id: requestID) {
            artwork = ImageCache.shared.cached(for: game, kind: kind, store: store)
            let result = await ImageCache.shared.image(for: game, kind: kind, store: store)
            guard !Task.isCancelled else { return }
            artwork = result
        }
        .accessibilityLabel("\(game.name) 游戏原画")
    }
}
