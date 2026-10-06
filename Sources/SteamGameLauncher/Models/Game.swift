import Foundation

struct Game: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var installPath: String?
    var libraryPath: String?
    var sizeOnDisk: Int64 = 0
    var installed = false
    var playtimeMinutes: Int?
    var lastPlayed: Date?
    var addedManually = false
    var metadata: GameMetadata?
    var localTarget: LocalTarget?
    var owned: Bool?

    var playtimeLabel: String {
        guard let minutes = playtimeMinutes else { return "尚无时长记录" }
        return minutes >= 60 ? String(format: "%.1f 小时", Double(minutes) / 60) : "\(minutes) 分钟"
    }
    var lastPlayedLabel: String {
        guard let date = lastPlayed else { return "准备好下一次冒险" }
        return "上次游玩 · \(date.formatted(.relative(presentation: .named)))"
    }
    var platformLabel: String {
        if let localTarget { return localTarget.kind == .application ? "macOS" : localTarget.kind.label }
        guard let meta = metadata else { return "平台待确认" }
        let platforms = [(meta.mac, "macOS"), (meta.windows, "Windows"), (meta.linux, "Linux")].filter { $0.0 }.map { $0.1 }
        return platforms.isEmpty ? "平台待确认" : platforms.joined(separator: " / ")
    }
    var nonMacPlatforms: [GamePlatform] {
        guard isSteam, let metadata, !metadata.mac else { return [] }
        return GamePlatform.allCases.filter { platform in
            platform == .windows ? metadata.windows : metadata.linux
        }
    }
    var launchable: Bool { installed }
    var isSteam: Bool { localTarget == nil }
    var entryLabel: String { localTarget?.kind.label ?? (installed ? "已在本机安装" : owned == true ? "在库里 · 未安装" : "Steam 快捷入口") }
    var launchLabel: String { isSteam ? (installed ? "开始游戏" : "在 Steam 中查看") : "打开" }
}

struct LocalTarget: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case application, shell, command, jar, python, javascript, executable, document
        var label: String {
            switch self {
            case .application: "本地应用"
            case .shell, .command: "Shell 脚本"
            case .jar: "Java"
            case .python: "Python"
            case .javascript: "Node.js"
            case .executable: "可执行文件"
            case .document: "本地文件"
            }
        }
    }
    var path: String
    var kind: Kind
    var arguments: [String] = []
    static func classify(_ url: URL) -> Kind {
        switch url.pathExtension.lowercased() {
        case "app": .application
        case "sh": .shell
        case "command": .command
        case "jar": .jar
        case "py": .python
        case "js", "mjs", "cjs": .javascript
        default: FileManager.default.isExecutableFile(atPath: url.path) ? .executable : .document
        }
    }
}

struct GameMetadata: Codable, Hashable, Sendable {
    var name: String
    var summary: String
    var genres: [String]
    var developers: [String]
    var mac: Bool
    var windows: Bool
    var linux: Bool
    var headerURL: String?
    var fetchedAt: Date = Date()
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "全部", installed = "已安装", owned = "在库里", windows = "Windows", linux = "Linux", favorites = "收藏", recent = "最近游玩", local = "本地应用", shortcuts = "快捷入口", hidden = "隐藏"
    var id: String { rawValue }
}
enum GameSort: String, CaseIterable, Identifiable {
    case recent = "最近游玩", name = "名称", playtime = "游玩时长", size = "安装大小"
    var id: String { rawValue }
}
enum Destination: String, CaseIterable {
    case home = "现在玩", library = "游戏库", favorites = "收藏"
}
enum WallDirection: String, Codable, CaseIterable, Identifiable {
    case diagonal = "倾斜横向", horizontal = "横向", vertical = "竖向"
    var id: String { rawValue }
}
enum WallSource: String, Codable, CaseIterable, Identifiable {
    case cached = "Steam 缓存海报", library = "全部游戏", installed = "已安装", favorites = "收藏"
    var id: String { rawValue }
}
enum ArtworkKind: String, Sendable {
    case poster, hero, logo, header
    var filenames: [String] {
        switch self {
        case .poster: return ["library_600x900_2x.jpg", "library_600x900.jpg", "library_600x900_schinese.jpg", "portrait.png"]
        case .hero: return ["library_hero.jpg", "library_hero_schinese.jpg", "header.jpg"]
        case .logo: return ["logo.png", "logo_schinese.png"]
        case .header: return ["header.jpg", "library_hero.jpg"]
        }
    }
    var remoteFilename: String {
        switch self {
        case .poster: return "library_600x900.jpg"
        case .hero: return "library_hero.jpg"
        case .logo: return "logo.png"
        case .header: return "header.jpg"
        }
    }
}

enum GamePlatform: String, CaseIterable, Identifiable {
    case windows = "Windows", linux = "Linux"
    var id: String { rawValue }
}
