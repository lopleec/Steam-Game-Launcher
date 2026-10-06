import Foundation

struct ScanResult: Sendable {
    var games: [Game]
    var libraries: [String]
    var warnings: [String]
    var steamFound: Bool
    var cachedPosterIDs: [String] = []
}

struct SteamScanner: Sendable {
    static var defaultRoot: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam").path
    }
    func scan(root: String, additionalLibraries: [String]) -> ScanResult {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root, isDirectory: true).resolvingSymlinksInPath()
        var paths = [root] + additionalLibraries
        var warnings = [String]()
        for relative in ["steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"] {
            let file = rootURL.appendingPathComponent(relative)
            guard fm.fileExists(atPath: file.path) else { continue }
            do {
                let folders = try VDFParser.read(file).node("libraryfolders")
                for entry in folders?.entries ?? [] where Int(entry.key) != nil {
                    if let path = entry.value.node?.string("path") ?? entry.value.string { paths.append(path) }
                }
            } catch { warnings.append("无法读取游戏库索引：\(file.lastPathComponent)") }
        }
        paths = Array(Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })).sorted()
        var games = [String: Game]()
        var foundLibraries = [String]()
        for path in paths {
            let library = URL(fileURLWithPath: path, isDirectory: true)
            let steamapps = library.lastPathComponent.lowercased() == "steamapps" ? library : library.appendingPathComponent("steamapps")
            guard fm.fileExists(atPath: steamapps.path) else {
                if additionalLibraries.contains(path) { warnings.append("游戏库离线或不存在：\(path)") }
                continue
            }
            foundLibraries.append(library.path)
            do {
                let manifests = try fm.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }.sorted { $0.path < $1.path }
                for file in manifests {
                    do {
                        guard let state = try VDFParser.read(file).node("AppState"),
                              let id = state.string("appid"), SteamLink.validAppID(id),
                              let name = state.string("name") else { throw VDFParser.ParseError.malformed }
                        let directory = state.string("installdir") ?? ""
                        let install = steamapps.appendingPathComponent("common").appendingPathComponent(directory).standardizedFileURL
                        let common = steamapps.appendingPathComponent("common").standardizedFileURL.path + "/"
                        let validDirectory = !directory.isEmpty && install.path.hasPrefix(common)
                        let flags = Int(state.string("StateFlags") ?? "0") ?? 0
                        var game = Game(id: id, name: name)
                        game.installPath = validDirectory ? install.path : nil
                        game.libraryPath = library.path
                        game.installed = validDirectory && fm.fileExists(atPath: install.path) && (flags & 4) != 0
                        game.sizeOnDisk = Int64(state.string("SizeOnDisk") ?? "0") ?? 0
                        if let time = Double(state.string("LastPlayed") ?? ""), time > 0 { game.lastPlayed = Date(timeIntervalSince1970: time) }
                        if games[id] == nil || (!games[id]!.installed && game.installed) { games[id] = game }
                    } catch { warnings.append("已跳过损坏的清单：\(file.lastPathComponent)") }
                }
            } catch { warnings.append("无法读取游戏库：\(path)") }
        }
        // Only read the newest local activity file. No login tokens or account credentials are used.
        let userdata = rootURL.appendingPathComponent("userdata")
        let users = (try? fm.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil)) ?? []
        let configs = users.map { $0.appendingPathComponent("config/localconfig.vdf") }
            .filter { fm.fileExists(atPath: $0.path) }
            .sorted { modified($0) > modified($1) }
        if let file = configs.first,
           let node = try? VDFParser.read(file),
           let apps = node.path("UserLocalConfigStore", "Software", "Valve", "Steam", "apps") {
            for entry in apps.entries {
                guard var game = games[entry.key], let activity = entry.value.node else { continue }
                if let minutes = Int(activity.string("Playtime") ?? ""), minutes >= 0 { game.playtimeMinutes = minutes }
                if let time = Double(activity.string("LastPlayed") ?? ""), time > 0 {
                    let date = Date(timeIntervalSince1970: time)
                    game.lastPlayed = max(game.lastPlayed ?? .distantPast, date)
                }
                games[entry.key] = game
            }
        }
        let cache = rootURL.appendingPathComponent("appcache/librarycache").resolvingSymlinksInPath()
        var posterIDs = Set<String>()
        if let enumerator = fm.enumerator(at: cache, includingPropertiesForKeys: nil) {
            while let file = enumerator.nextObject() as? URL {
                let name = file.lastPathComponent
                if name.contains("library_600x900") {
                    let relative = String(file.resolvingSymlinksInPath().path.dropFirst(cache.path.count + 1))
                    if let id = relative.split(separator: "/").first.map(String.init), SteamLink.validAppID(id) { posterIDs.insert(id) }
                    else if let id = name.split(separator: "_").first.map(String.init), SteamLink.validAppID(id) { posterIDs.insert(id) }
                }
            }
        }
        return ScanResult(games: games.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                          libraries: foundLibraries, warnings: warnings, steamFound: fm.fileExists(atPath: rootURL.path),
                          cachedPosterIDs: posterIDs.sorted { (UInt64($0) ?? 0) < (UInt64($1) ?? 0) })
    }
    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
