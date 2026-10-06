import Foundation

struct SteamAccountSnapshot: Codable, Equatable, Sendable {
    var steamID: String
    var displayName: String
    var syncedAt: Date
    var games: [Game]
}

struct SteamOwnedGamesResponse: Decodable {
    struct Response: Decodable {
        struct OwnedGame: Decodable {
            var appid: UInt64
            var name: String?
            var playtime_forever: Int?
            var rtime_last_played: Int?
        }
        var game_count: Int?
        var games: [OwnedGame]?
    }
    var response: Response
    func snapshot(steamID: String, displayName: String) throws -> SteamAccountSnapshot {
        guard let count = response.game_count, count >= 0,
              count == (response.games ?? []).count else { throw SteamSyncError.incompleteLibrary }
        var seen = Set<String>()
        let games = (response.games ?? []).compactMap { item -> Game? in
            let id = String(item.appid)
            guard SteamLink.validAppID(id), seen.insert(id).inserted else { return nil }
            var game = Game(id: id, name: item.name ?? "Steam App \(id)", playtimeMinutes: item.playtime_forever)
            game.owned = true
            if let time = item.rtime_last_played, time > 0 { game.lastPlayed = Date(timeIntervalSince1970: Double(time)) }
            return game
        }
        guard games.count == count else { throw SteamSyncError.incompleteLibrary }
        return .init(steamID: steamID, displayName: displayName, syncedAt: Date(), games: games)
    }
}

enum SteamSyncError: LocalizedError {
    case signInRequired, incompleteLibrary, unavailable, cancelled
    var errorDescription: String? {
        switch self {
        case .signInRequired: "Steam 会话已过期，请在官方页面重新登录。"
        case .incompleteLibrary: "Steam 未返回完整的游戏库。原有本地缓存已保留，请稍后重试。"
        case .unavailable: "暂时无法读取 Steam 游戏库，请检查网络并重试。原有本地缓存已保留。"
        case .cancelled: "同步已取消。"
        }
    }
}

enum LibraryMerger {
    static func merge(installed: [Game], account: [Game], manual: [Game], previous: [Game]) -> [Game] {
        let old = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = installed.filter { $0.installed && $0.isSteam }.map { game in var entry = game; entry.owned = nil; return entry }
        for owned in account {
            if let index = result.firstIndex(where: { $0.id == owned.id }) {
                result[index].owned = true
                if let minutes = owned.playtimeMinutes { result[index].playtimeMinutes = minutes }
                result[index].lastPlayed = owned.lastPlayed
            } else { var entry = owned; entry.installed = false; entry.installPath = nil; result.append(entry) }
        }
        for var entry in manual {
            if let target = entry.localTarget { entry.installed = FileManager.default.fileExists(atPath: target.path) }
            if !result.contains(where: { $0.id == entry.id }) { result.append(entry) }
        }
        for index in result.indices { result[index].metadata = old[result[index].id]?.metadata ?? result[index].metadata }
        return result
    }
}
