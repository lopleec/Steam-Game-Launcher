import Foundation

struct Preferences: Codable, Equatable {
    var steamRoot = SteamScanner.defaultRoot
    var additionalLibraries: [String] = []
    var onlineArtwork = true
    var onlineMetadata = true
    var minimizeOnLaunch = true
    var automaticRescan = true
    var appearance = "深色"
    var posterWidth = 172.0
    var idleEnabled = true
    var idleMinutes = 5.0
    var wallDirection: WallDirection = .diagonal
    var wallSource: WallSource = .cached
    var wallSpeed = 24.0
    var wallPosterWidth = 200.0
    var wallGap = 16.0
    var wallAngle = -12.0
    var wallBrightness = 0.82
    var wallReverse = false
    var wallClock = true
    var wallFullscreen = true
    var wallAlternating = true
    init() {}
    private enum CodingKeys: String, CodingKey {
        case steamRoot, additionalLibraries, onlineArtwork, onlineMetadata, minimizeOnLaunch, automaticRescan, appearance, posterWidth, idleEnabled, idleMinutes, wallDirection, wallSource, wallSpeed, wallPosterWidth, wallGap, wallAngle, wallBrightness, wallReverse, wallClock, wallFullscreen, wallAlternating
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // New settings and obsolete enum values must not discard the user's library.
        func read<T: Decodable>(_ key: CodingKeys, default fallback: T) -> T {
            (try? values.decode(T.self, forKey: key)) ?? fallback
        }
        steamRoot = read(.steamRoot, default: steamRoot)
        additionalLibraries = read(.additionalLibraries, default: additionalLibraries)
        onlineArtwork = read(.onlineArtwork, default: onlineArtwork)
        onlineMetadata = read(.onlineMetadata, default: onlineMetadata)
        minimizeOnLaunch = read(.minimizeOnLaunch, default: minimizeOnLaunch)
        automaticRescan = read(.automaticRescan, default: automaticRescan)
        appearance = read(.appearance, default: appearance)
        posterWidth = read(.posterWidth, default: posterWidth)
        idleEnabled = read(.idleEnabled, default: idleEnabled)
        idleMinutes = read(.idleMinutes, default: idleMinutes)
        wallDirection = read(.wallDirection, default: wallDirection)
        wallSource = read(.wallSource, default: wallSource)
        wallSpeed = read(.wallSpeed, default: wallSpeed)
        wallPosterWidth = read(.wallPosterWidth, default: wallPosterWidth)
        wallGap = read(.wallGap, default: wallGap)
        wallAngle = read(.wallAngle, default: wallAngle)
        wallBrightness = read(.wallBrightness, default: wallBrightness)
        wallReverse = read(.wallReverse, default: wallReverse)
        wallClock = read(.wallClock, default: wallClock)
        wallFullscreen = read(.wallFullscreen, default: wallFullscreen)
        wallAlternating = read(.wallAlternating, default: wallAlternating)
        func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        posterWidth = bounded(posterWidth, 130...260, fallback: 172)
        idleMinutes = bounded(idleMinutes, 1...30, fallback: 5)
        wallSpeed = bounded(wallSpeed, 8...80, fallback: 24)
        wallPosterWidth = bounded(wallPosterWidth, 130...320, fallback: 200)
        wallGap = bounded(wallGap, 4...32, fallback: 16)
        wallAngle = bounded(wallAngle, -25...25, fallback: -12)
        wallBrightness = bounded(wallBrightness, 0.3...1, fallback: 0.82)
    }

}

struct GameCollection: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var gameIDs: Set<String> = []
}
struct SavedLibrary: Codable {
    var preferences = Preferences()
    var favorites: Set<String> = []
    var hidden: Set<String> = []
    var manualGames: [Game] = []
    var collections: [GameCollection] = []
    var launches: [String: Date] = [:]
    var customArtwork: [String: String] = [:]
    var removedGames: [Game] = []
    var hiddenPassword: HiddenPasswordRecord?
    var steamAccount: SteamAccountSnapshot?
    var setupCompleted = false

    init() {}
    enum CodingKeys: String, CodingKey {
        case preferences, favorites, hidden, manualGames, collections, launches, customArtwork, removedGames, hiddenPassword, steamAccount, setupCompleted
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferences = try container.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        favorites = try container.decodeIfPresent(Set<String>.self, forKey: .favorites) ?? []
        hidden = try container.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? []
        manualGames = try container.decodeIfPresent([Game].self, forKey: .manualGames) ?? []
        collections = try container.decodeIfPresent([GameCollection].self, forKey: .collections) ?? []
        launches = try container.decodeIfPresent([String: Date].self, forKey: .launches) ?? [:]
        customArtwork = try container.decodeIfPresent([String: String].self, forKey: .customArtwork) ?? [:]
        removedGames = try container.decodeIfPresent([Game].self, forKey: .removedGames) ?? []
        hiddenPassword = try container.decodeIfPresent(HiddenPasswordRecord.self, forKey: .hiddenPassword)
        steamAccount = try container.decodeIfPresent(SteamAccountSnapshot.self, forKey: .steamAccount)
        setupCompleted = try container.decodeIfPresent(Bool.self, forKey: .setupCompleted) ?? false
    }
}

enum LibraryPersistence {
    private static let queue = DispatchQueue(label: "com.lopleec.SteamGameLauncher.persistence", qos: .utility)
    static func write(_ snapshot: SavedLibrary) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do { try AppFiles.save(snapshot, name: "library.json"); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    static func flush(_ snapshot: SavedLibrary) throws {
        // Finish earlier writes before saving the final snapshot at app termination.
        try queue.sync { try AppFiles.save(snapshot, name: "library.json") }
    }
}

enum AppFiles {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SteamGameLauncher", isDirectory: true)
    }
    static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static func save<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
