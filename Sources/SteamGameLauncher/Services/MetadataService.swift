import Foundation

actor MetadataService {
    static let shared = MetadataService()
    static let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60
    static func needsRefresh(_ metadata: GameMetadata?) -> Bool {
        guard let metadata else { return true }
        return Date().timeIntervalSince(metadata.fetchedAt) >= cacheLifetime
    }
    func invalidate() {
        for id in Array(cache.keys) { cache[id]?.fetchedAt = .distantPast }
        try? AppFiles.save(cache, name: "metadata.json")
    }
    private var cache = AppFiles.load("metadata.json", as: [String: GameMetadata].self) ?? [:]
    func metadata(id: String, online: Bool) async -> GameMetadata? {
        let existing = cache[id]
        if let existing, !online || !Self.needsRefresh(existing) { return existing }
        guard online, SteamLink.validAppID(id), let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(id)&l=schinese") else { return existing }
        var request = URLRequest(url: url); request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wrapper = object[id] as? [String: Any], wrapper["success"] as? Bool == true,
              let game = wrapper["data"] as? [String: Any], let name = game["name"] as? String else { return existing }
        let platforms = game["platforms"] as? [String: Bool] ?? [:]
        let genres = (game["genres"] as? [[String: Any]] ?? []).compactMap { $0["description"] as? String }
        let raw = game["short_description"] as? String ?? ""
        let summary = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
        let meta = GameMetadata(name: name, summary: summary, genres: genres, developers: game["developers"] as? [String] ?? [],
                                mac: platforms["mac"] ?? false, windows: platforms["windows"] ?? false,
                                linux: platforms["linux"] ?? false, headerURL: game["header_image"] as? String)
        cache[id] = meta
        try? AppFiles.save(cache, name: "metadata.json")
        return meta
    }
}
