import AppKit
import Observation
import UniformTypeIdentifiers

@Observable @MainActor final class LibraryStore {
    var saved: SavedLibrary {
        didSet { persist() }
    }
    var preferences: Preferences {
        get { saved.preferences }
        set { saved.preferences = newValue }
    }
    var games: [Game] = []
    var libraries: [String] = []
    var cachedPosterIDs: [String] = []
    var warnings: [String] = []
    var isScanning = false
    var steamFound = false
    var lastScan: Date?
    var search = ""
    var filter: LibraryFilter = .all
    var sort: GameSort = .recent
    var destination: Destination = .home
    var collectionID: UUID?
    var selectedGame: Game?
    var showingAddGame = false
    var showingSteamLogin = false
    var showingSetup: Bool
    @ObservationIgnored weak var accountSession: SteamAccountSession?
    var showingCollections = false
    var showingRemoved = false
    var editingLocalGame: Game?
    var showingUnlock = false
    var hiddenUnlocked = false
    var showingWall = false
    var automaticWall = false
    var message: String?
    var errorMessage: String?
    var heroID: String?
    var artworkRevision = 0
    @ObservationIgnored weak var mainWindow: NSWindow?
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var hiddenGeneration = 0
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private let persistenceEnabled: Bool

    init(saved: SavedLibrary? = nil, persistenceEnabled: Bool = true) {
        self.persistenceEnabled = persistenceEnabled
        let restored = saved ?? AppFiles.load("library.json", as: SavedLibrary.self) ?? SavedLibrary()
        self.saved = restored
        showingSetup = !restored.setupCompleted
        if persistenceEnabled {
            terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            }
        }
    }
    deinit { if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) } }
    var hiddenGames: [Game] { hiddenUnlocked ? games.filter { saved.hidden.contains($0.id) } : [] }
    var recoverableGames: [Game] { saved.removedGames.filter { hiddenUnlocked || !saved.hidden.contains($0.id) } }
    var visibleGames: [Game] { games.filter { !saved.hidden.contains($0.id) } }
    var recentGames: [Game] {
        visibleGames.filter { activityDate($0) != nil }.sorted { (activityDate($0) ?? .distantPast) > (activityDate($1) ?? .distantPast) }
    }
    var heroGame: Game? { visibleGames.first { $0.id == heroID } ?? recentGames.first ?? visibleGames.first }
    var favoriteGames: [Game] { visibleGames.filter { saved.favorites.contains($0.id) } }
    var wallGames: [Game] {
        switch preferences.wallSource {
        case .cached:
            let cached = cachedPosterIDs.filter { id in !saved.hidden.contains(id) && !saved.removedGames.contains(where: { $0.id == id }) }.map { id in games.first { $0.id == id } ?? Game(id: id, name: "Steam \(id)") }
            return cached.isEmpty ? visibleGames : cached
        case .library: return visibleGames
        case .installed: return visibleGames.filter(\.installed)
        case .favorites: return favoriteGames
        }
    }
    var filteredGames: [Game] {
        var result = filter == .hidden ? hiddenGames : visibleGames
        if destination == .favorites { result = result.filter { saved.favorites.contains($0.id) } }
        if let collectionID, let collection = saved.collections.first(where: { $0.id == collectionID }) { result = result.filter { collection.gameIDs.contains($0.id) } }
        switch filter {
        case .all: break
        case .installed: result = result.filter(\.installed)
        case .owned: result = result.filter { $0.owned == true }
        case .windows: result = result.filter { $0.isSteam && $0.metadata?.windows == true }
        case .linux: result = result.filter { $0.isSteam && $0.metadata?.linux == true }
        case .favorites: result = result.filter { saved.favorites.contains($0.id) }
        case .recent: result = result.filter { activityDate($0) != nil }
        case .local: result = result.filter { !$0.isSteam }
        case .shortcuts: result = result.filter { $0.isSteam && $0.addedManually && !$0.installed }
        case .hidden: break
        }
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.id.contains(search) || ($0.metadata?.name.localizedCaseInsensitiveContains(search) ?? false) }
        }
        return result.sorted {
            switch sort {
            case .name: return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            case .recent:
                let left = activityDate($0) ?? .distantPast, right = activityDate($1) ?? .distantPast
                return left == right ? $0.name < $1.name : left > right
            case .playtime:
                let left = $0.playtimeMinutes ?? -1, right = $1.playtimeMinutes ?? -1
                return left == right ? $0.name < $1.name : left > right
            case .size: return $0.sizeOnDisk == $1.sizeOnDisk ? $0.name < $1.name : $0.sizeOnDisk > $1.sizeOnDisk
            }
        }
    }
    func activityDate(_ game: Game) -> Date? {
        [game.lastPlayed, saved.launches[game.id]].compactMap { $0 }.max()
    }
    func scan() async {
        guard !isScanning else { return }
        isScanning = true; scanGeneration += 1
        let generation = scanGeneration, root = preferences.steamRoot, extra = preferences.additionalLibraries
        let result = await Task.detached(priority: .userInitiated) { SteamScanner().scan(root: root, additionalLibraries: extra) }.value
        if root != preferences.steamRoot || extra != preferences.additionalLibraries {
            isScanning = false; await scan(); return
        }
        let merged = LibraryMerger.merge(installed: result.games, account: saved.steamAccount?.games ?? [], manual: saved.manualGames, previous: games)
        if games != merged { games = merged }; libraries = result.libraries; warnings = result.warnings; steamFound = result.steamFound
        cachedPosterIDs = result.cachedPosterIDs
        lastScan = Date(); isScanning = false
        let online = preferences.onlineMetadata
        // Limit public metadata requests to three at a time; the scan itself never waits on the network.
        await withTaskGroup(of: (String, GameMetadata?).self) { group in
            var iterator = merged.filter { $0.isSteam && MetadataService.needsRefresh($0.metadata) }.prefix(36).makeIterator()
            for _ in 0..<3 {
                if let game = iterator.next() { group.addTask { (game.id, await MetadataService.shared.metadata(id: game.id, online: online)) } }
            }
            for await (id, meta) in group {
                guard generation == scanGeneration else { group.cancelAll(); break }
                if let index = games.firstIndex(where: { $0.id == id }), let meta, games[index].metadata != meta { games[index].metadata = meta }
                if let game = iterator.next() { group.addTask { (game.id, await MetadataService.shared.metadata(id: game.id, online: online)) } }
            }
        }
    }
    func refreshMetadata() async {
        guard !isScanning else { return }
        await MetadataService.shared.invalidate()
        for index in games.indices { games[index].metadata?.fetchedAt = .distantPast }
        ImageCache.shared.clear(); artworkRevision += 1
        await scan()
    }
    func loadMetadata(for id: String) async {
        guard let game = games.first(where: { $0.id == id }), game.isSteam,
              MetadataService.needsRefresh(game.metadata) else { return }
        guard let metadata = await MetadataService.shared.metadata(id: id, online: preferences.onlineMetadata),
              let index = games.firstIndex(where: { $0.id == id }) else { return }
        if games[index].metadata != metadata { games[index].metadata = metadata }
    }
    var availableFilters: [LibraryFilter] {
        LibraryFilter.allCases.filter { saved.steamAccount != nil || ($0 != .installed && $0 != .owned && $0 != .windows && $0 != .linux) }
    }
    func beginSteamLogin() { showingSteamLogin = true; accountSession?.beginLogin() }
    func applyAccountSnapshot(_ account: SteamAccountSnapshot) {
        saved.steamAccount = account
        games = LibraryMerger.merge(installed: games, account: account.games, manual: saved.manualGames, previous: games)
        toast("已同步 Steam 游戏库")
        Task { await scan() }
    }
    func removeAccountCache() {
        saved.steamAccount = nil
        games = LibraryMerger.merge(installed: games, account: [], manual: saved.manualGames, previous: games)
        if !availableFilters.contains(filter) { filter = .all }
    }
    func navigate(_ destination: Destination) {
        lockHidden(); self.destination = destination; collectionID = nil; filter = .all; search = ""
    }
    func toggleFavorite(_ game: Game) {
        if saved.favorites.contains(game.id) { saved.favorites.remove(game.id) } else { saved.favorites.insert(game.id) }
    }
    func hide(_ game: Game) { saved.hidden.insert(game.id); selectedGame = nil; toast("已移至隐藏分类") }
    func unhide(_ game: Game) {
        guard hiddenUnlocked else { return }
        saved.hidden.remove(game.id); selectedGame = nil; toast("已恢复到游戏库")
    }
    func selectFilter(_ value: LibraryFilter) {
        if filter == .hidden && value != .hidden { lockHidden() }
        filter = value; collectionID = nil
        if value == .hidden { destination = .library; search = "" }
    }
    func requestHiddenDisplay() {
        if saved.hiddenPassword == nil { hiddenUnlocked = true }
        else if !hiddenUnlocked { showingUnlock = true }
    }
    func lockHidden() {
        hiddenGeneration += 1; hiddenUnlocked = false
        if let editingLocalGame, saved.hidden.contains(editingLocalGame.id) { self.editingLocalGame = nil }
        if let selectedGame, saved.hidden.contains(selectedGame.id) { self.selectedGame = nil }
    }
    func unlockHidden(password: String) async -> Bool {
        let record = saved.hiddenPassword, generation = hiddenGeneration
        let valid = await Task.detached { record.map { HiddenPassword.verify(password, record: $0) } ?? true }.value
        // Do not grant an outdated request if the password changed while deriving.
        guard valid, generation == hiddenGeneration, saved.hiddenPassword == record, filter == .hidden else { return false }
        hiddenUnlocked = true; return true
    }
    func configurePassword(current: String, new: String?) async -> Bool {
        let oldRecord = saved.hiddenPassword
        let result = await Task.detached { () -> (Bool, HiddenPasswordRecord?) in
            if let oldRecord, !HiddenPassword.verify(current, record: oldRecord) { return (false, nil) }
            if let new {
                guard !new.isEmpty, let record = try? HiddenPassword.create(new) else { return (false, nil) }
                return (true, record)
            }
            return (true, nil)
        }.value
        guard result.0, saved.hiddenPassword == oldRecord else { return false }
        saved.hiddenPassword = result.1; lockHidden(); return true
    }
    func restorePreferences(rescan: Bool = true) {
        preferences = Preferences(); ImageCache.shared.clear(); artworkRevision += 1
        toast("已还原初始设置"); if rescan { Task { await scan() } }
    }
    func finishSetup(_ preferences: Preferences, rescan: Bool = true) {
        saved.preferences = preferences
        saved.setupCompleted = true
        showingSetup = false
        ImageCache.shared.clear(); artworkRevision += 1
        flush()
        if rescan { Task { await scan() } }
    }
    func reopenSetup() {
        showingWall = false; selectedGame = nil; lockHidden()
        showingSetup = true
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp?.activate(ignoringOtherApps: true)
    }
    func launch(_ game: Game) {
        guard !saved.hidden.contains(game.id) || hiddenUnlocked else { return }
        if !game.isSteam {
            do {
                try LocalLauncher.shared.launch(game) { [weak self] error in if let error { self?.errorMessage = error } }
                saved.launches[game.id] = Date(); toast("已打开 \(game.name)")
                if preferences.minimizeOnLaunch { mainWindow?.miniaturize(nil) }
            } catch { errorMessage = error.localizedDescription }
            return
        }
        guard game.installed else { action(.library, game: game); return }
        guard let url = SteamLink.url(.play, id: game.id), SteamLink.open(url) else { errorMessage = "未找到 Steam。请先安装 Steam 或检查默认链接处理程序。"; return }
        saved.launches[game.id] = Date(); toast("已交给 Steam 启动 \(game.name)")
        if preferences.minimizeOnLaunch { mainWindow?.miniaturize(nil) }
    }
    func action(_ action: SteamLink.GameAction, game: Game) {
        if action == .play { launch(game); return }
        guard game.isSteam, let url = SteamLink.url(action, id: game.id), SteamLink.open(url) else { errorMessage = "无法打开 Steam 链接，请确认 Steam 已安装。"; return }
    }
    func openSteam(_ destination: SteamLink.Destination) {
        if !SteamLink.open(destination.url) { errorMessage = "无法打开 Steam，请确认客户端已安装。" }
    }
    func reveal(_ game: Game) {
        if let path = game.installPath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    }
    func copyLaunchLink(_ game: Game) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(game.localTarget.map { URL(fileURLWithPath: $0.path).absoluteString } ?? "steam://rungameid/\(game.id)", forType: .string)
        toast("已复制启动链接")
    }
    func addManual(id input: String, name: String) -> Bool {
        let id = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SteamLink.validAppID(id) else { errorMessage = "App ID 必须是有效的正整数。"; return false }
        guard !saved.removedGames.contains(where: { $0.id == id }) else { toast("入口已移除，请在“恢复入口”中恢复"); return false }
        guard !games.contains(where: { $0.id == id }) else { toast("这款游戏已在游戏库中"); return false }
        var game = Game(id: id, name: name.isEmpty ? "Steam App \(id)" : name)
        game.addedManually = true; saved.manualGames.append(game); games.append(game)
        Task {
            if let meta = await MetadataService.shared.metadata(id: id, online: preferences.onlineMetadata), let index = games.firstIndex(where: { $0.id == id }) {
                games[index].metadata = meta
                if let manualIndex = saved.manualGames.firstIndex(where: { $0.id == id }) { saved.manualGames[manualIndex].metadata = meta }
                if name.isEmpty { games[index].name = meta.name; if let manualIndex = saved.manualGames.firstIndex(where: { $0.id == id }) { saved.manualGames[manualIndex].name = meta.name } }
            }
        }
        return true
    }
    func removeManual(_ game: Game) {
        guard game.addedManually else { return }
        if !saved.removedGames.contains(where: { $0.id == game.id }) { saved.removedGames.append(game) }
        saved.manualGames.removeAll { $0.id == game.id }; games.removeAll { $0.id == game.id }; selectedGame = nil
        toast("入口已移除，可在“恢复入口”中找回")
    }
    func restoreManual(_ game: Game) {
        guard !saved.hidden.contains(game.id) || hiddenUnlocked else { return }
        if !saved.manualGames.contains(where: { $0.id == game.id }) { saved.manualGames.append(game) }
        if !games.contains(where: { $0.id == game.id }) { games.append(game) }
        saved.removedGames.removeAll { $0.id == game.id }; toast("已恢复入口")
    }
    func chooseLocalEntries() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false; panel.allowsMultipleSelection = true
        panel.message = "选择应用、脚本、JAR 或其他本地文件"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addLocal(url: url) }
    }
    @discardableResult func addLocal(url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else { return false }
        if games.contains(where: { $0.localTarget?.path == path }) { toast("这个文件已有入口"); return false }
        if let removed = saved.removedGames.first(where: { $0.localTarget?.path == path }) { restoreManual(removed); return true }
        let kind = LocalTarget.classify(url)
        let bundleName = kind == .application ? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String : nil
        var game = Game(id: "local-" + UUID().uuidString, name: bundleName ?? url.deletingPathExtension().lastPathComponent,
                        installPath: path, installed: true, addedManually: true)
        game.localTarget = LocalTarget(path: path, kind: kind)
        saved.manualGames.append(game); games.append(game); toast("已添加 \(game.name)")
        return true
    }
    func updateLocalArguments(_ game: Game, arguments: [String]) {
        guard var target = game.localTarget else { return }
        target.arguments = arguments
        if let index = games.firstIndex(where: { $0.id == game.id }) { games[index].localTarget = target }
        if let index = saved.manualGames.firstIndex(where: { $0.id == game.id }) { saved.manualGames[index].localTarget = target }
    }
    func showLocalLog(_ game: Game) {
        let url = LocalLauncher.logURL(for: game.id)
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
        else { toast("启动脚本后会生成运行日志") }
    }
    func chooseFolder(asSteamRoot: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = asSteamRoot ? "选择 Steam 根目录（包含 steamapps 和 appcache）" : "选择游戏库目录或 steamapps 文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if asSteamRoot { preferences.steamRoot = url.path }
        else if !preferences.additionalLibraries.contains(url.path) { preferences.additionalLibraries.append(url.path) }
        ImageCache.shared.clear(); Task { await scan() }
    }
    func chooseArtwork(_ game: Game, kind: ArtworkKind) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Copy custom artwork into app data so moving the original file does not break the cover.
        let folder = AppFiles.directory.appendingPathComponent("CustomArtwork")
        let target = folder.appendingPathComponent("\(game.id)_\(kind.rawValue).\(url.pathExtension)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: url, to: target)
            saved.customArtwork["\(game.id)_\(kind.rawValue)"] = target.path; ImageCache.shared.clear(); artworkRevision += 1
        } catch { errorMessage = "保存自定义原画失败：\(error.localizedDescription)" }
    }
    func toggleCollection(_ game: Game, collection: GameCollection) {
        guard let index = saved.collections.firstIndex(where: { $0.id == collection.id }) else { return }
        if saved.collections[index].gameIDs.contains(game.id) { saved.collections[index].gameIDs.remove(game.id) }
        else { saved.collections[index].gameIDs.insert(game.id) }
    }
    func startWall(automatic: Bool = false) {
        guard !wallGames.isEmpty else { toast("当前海报墙来源没有游戏，请在设置中更换来源"); return }
        automaticWall = automatic; showingWall = true
        if !automatic { mainWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    func toast(_ text: String) {
        messageTask?.cancel(); message = text
        messageTask = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { message = nil } }
    }
    func flush() {
        guard persistenceEnabled else { return }
        persistenceTask?.cancel()
        do { try LibraryPersistence.flush(saved) }
        catch { errorMessage = error.localizedDescription }
    }
    private func persist() {
        guard persistenceEnabled else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.saved
            do { try await LibraryPersistence.write(snapshot) }
            catch { self.errorMessage = "无法保存偏好设置：\(error.localizedDescription)" }
        }
    }
}
