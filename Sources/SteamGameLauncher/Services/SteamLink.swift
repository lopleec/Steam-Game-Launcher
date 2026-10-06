import AppKit

enum SteamLink {
    enum GameAction: String, CaseIterable, Identifiable {
        case play = "启动游戏", store = "商店页面", library = "Steam 游戏详情", community = "社区中心"
        case achievements = "成就", guides = "指南", discussions = "讨论", workshop = "创意工坊", news = "更新与新闻", properties = "游戏属性"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .play: return "play.fill"
            case .store: return "bag"
            case .library: return "square.stack"
            case .community: return "person.2"
            case .achievements: return "trophy"
            case .guides: return "book"
            case .discussions: return "bubble.left.and.bubble.right"
            case .workshop: return "wrench.and.screwdriver"
            case .news: return "newspaper"
            case .properties: return "slider.horizontal.3"
            }
        }
    }
    enum Destination: String, CaseIterable, Identifiable {
        case library = "Steam 游戏库", store = "Steam 商店", friends = "好友", bigPicture = "大屏幕模式", settings = "Steam 设置"
        var id: String { rawValue }
        var url: URL {
            let path: String
            switch self {
            case .library: path = "nav/games"
            case .store: path = "store"
            case .friends: path = "open/friends"
            case .bigPicture: path = "open/bigpicture"
            case .settings: path = "settings"
            }
            return URL(string: "steam://" + path)!
        }
    }
    static func validAppID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) } && (UInt64(id) ?? 0) > 0 && id.count <= 20
    }
    static func url(_ action: GameAction, id: String) -> URL? {
        guard validAppID(id) else { return nil }
        let path: String
        switch action {
        case .play: path = "rungameid/\(id)"
        case .store: path = "store/\(id)"
        case .library: path = "nav/games/details/\(id)"
        case .properties: path = "gameproperties/\(id)"
        case .community: path = "openurl/https://steamcommunity.com/app/\(id)/"
        case .achievements: path = "openurl/https://steamcommunity.com/my/stats/\(id)/?tab=achievements"
        case .guides: path = "openurl/https://steamcommunity.com/app/\(id)/guides/"
        case .discussions: path = "openurl/https://steamcommunity.com/app/\(id)/discussions/"
        case .workshop: path = "openurl/https://steamcommunity.com/app/\(id)/workshop/"
        case .news: path = "openurl/https://store.steampowered.com/news/app/\(id)/"
        }
        return URL(string: "steam://" + path)
    }
    @MainActor static func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    @MainActor static var isAvailable: Bool { NSWorkspace.shared.urlForApplication(toOpen: URL(string: "steam://store")!) != nil }
}
