import XCTest
@testable import SteamGameLauncher

final class SteamGameLauncherTests: XCTestCase {
    func testValveKeyValuesHandlesNestedPathsCommentsAndEscapes() throws {
        var parser = VDFParser(#"""
        // an external library with spaces and escaped separators
        "libraryfolders" { "0" { "path" "D:\\Steam Games" "apps" { "413150" "42" } } "1" "/Volumes/Games" }
        "title" "A \"quoted\" title"
        "duplicate" "first" "duplicate" "second"
        """#)
        let root = try parser.parse()
        XCTAssertEqual(root.path("libraryfolders", "0")?.string("path"), "D:\\Steam Games")
        XCTAssertEqual(root.path("libraryfolders", "0", "apps")?.string("413150"), "42")
        XCTAssertEqual(root.string("title"), "A \"quoted\" title")
        XCTAssertEqual(root.entries.filter { $0.key == "duplicate" }.count, 2)
        for invalid in ["\"missing\"", "\"root\" { \"x\" \"y\"", "}", "\"unterminated"] {
            var parser = VDFParser(invalid)
            XCTAssertThrowsError(try parser.parse())
        }
    }
    func testScannerResolvesMultipleLibrariesAndReadsOnlyActivitySubtree() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let external = root.appendingPathComponent("External Library")
        defer { try? fm.removeItem(at: root) }
        func write(_ relative: String, _ text: String) throws {
            let file = root.appendingPathComponent(relative)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        try fm.createDirectory(at: root.appendingPathComponent("steamapps/common/Stardew Valley"), withIntermediateDirectories: true)
        try fm.createDirectory(at: external.appendingPathComponent("steamapps/common/Game B"), withIntermediateDirectories: true)
        try write("steamapps/libraryfolders.vdf", "\"libraryfolders\" { \"0\" { \"path\" \"\(root.path)\" } \"1\" { \"path\" \"\(external.path)\" } }")
        try write("steamapps/appmanifest_413150.acf", "\"AppState\" { \"appid\" \"413150\" \"name\" \"Stardew Valley\" \"StateFlags\" \"4\" \"installdir\" \"Stardew Valley\" \"SizeOnDisk\" \"1024\" }")
        try write("External Library/steamapps/appmanifest_2.acf", "\"AppState\" { \"appid\" \"2\" \"name\" \"Game B\" \"StateFlags\" \"4\" \"installdir\" \"Game B\" }")
        try write("steamapps/appmanifest_3.acf", "\"AppState\" { \"appid\" \"3\" \"name\" \"Partial Download\" \"StateFlags\" \"1\" \"installdir\" \"Missing\" }")
        try write("steamapps/appmanifest_4.acf", "\"AppState\" { \"appid\" \"4\" \"name\" \"Unsafe Path\" \"StateFlags\" \"4\" \"installdir\" \"../../outside\" }")
        try write("steamapps/appmanifest_bad.acf", "corrupted")
        try write("userdata/1/config/localconfig.vdf", "\"UserLocalConfigStore\" { \"other\" { \"413150\" \"irrelevant\" } \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { \"413150\" { \"Playtime\" \"121\" \"LastPlayed\" \"1700000000\" } } } } } }")
        try write("appcache/librarycache/413150/hash/library_600x900.jpg", "fixture")
        let result = SteamScanner().scan(root: root.path, additionalLibraries: [external.path])
        XCTAssertEqual(result.libraries.count, 2)
        XCTAssertEqual(result.games.count, 4)
        XCTAssertEqual(result.games.filter(\.installed).count, 2)
        let game = try XCTUnwrap(result.games.first { $0.id == "413150" })
        XCTAssertEqual(game.playtimeMinutes, 121)
        XCTAssertEqual(game.lastPlayed, Date(timeIntervalSince1970: 1700000000))
        XCTAssertNil(result.games.first { $0.id == "4" }?.installPath)
        XCTAssertEqual(result.cachedPosterIDs, ["413150"])
        XCTAssertEqual(result.warnings.count, 1)
    }
    func testSteamLinksRejectInjectedCommandsAndUseExpectedRoutes() throws {
        for id in ["0", "-1", "413150/foo", "413150?x=1", "٤١٣١٥٠", "", "999999999999999999999"] { XCTAssertFalse(SteamLink.validAppID(id)) }
        XCTAssertEqual(SteamLink.url(.play, id: "413150")?.absoluteString, "steam://rungameid/413150")
        XCTAssertEqual(SteamLink.url(.store, id: "413150")?.absoluteString, "steam://store/413150")
        XCTAssertEqual(SteamLink.url(.library, id: "413150")?.absoluteString, "steam://nav/games/details/413150")
        XCTAssertNil(SteamLink.url(.play, id: "bad"))
        for action in SteamLink.GameAction.allCases { XCTAssertNotNil(SteamLink.url(action, id: "413150")) }
    }
    func testWallLayoutKeepsArtContinuousAcrossWrapAndHandlesReverse() {
        let size = CGSize(width: 1000, height: 700)
        func tiles(_ time: Double, reverse: Bool = false) -> [WallTile] {
            WallLayout.tiles(size: size, width: 200, gap: 16, elapsed: time, speed: 24, vertical: false, alternating: false, reverse: reverse, gameCount: 6)
        }
        let before = tiles(8.999), after = tiles(9.001)
        for tile in before where tile.rect.origin.x > 0 && tile.rect.origin.x < 800 {
            XCTAssertTrue(after.contains { $0.gameIndex == tile.gameIndex && $0.rect.origin.y == tile.rect.origin.y && abs($0.rect.origin.x - tile.rect.origin.x) < 0.1 })
        }
        XCTAssertTrue(tiles(10000, reverse: true).allSatisfy { (0..<6).contains($0.gameIndex) })
        XCTAssertTrue(WallLayout.tiles(size: size, width: 200, gap: 16, elapsed: 5, speed: 24, vertical: true, alternating: true, reverse: true, gameCount: 0).isEmpty)
    }
}

final class LauncherRefinementTests: XCTestCase {
    func testOldLibraryMigrationPreservesUserState() throws {
        var saved = SavedLibrary()
        saved.favorites = ["413150"]; saved.hidden = ["2"]
        saved.manualGames = [Game(id: "2", name: "Shortcut", addedManually: true)]
        saved.preferences.posterWidth = 199
        let data = try JSONEncoder().encode(saved)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "removedGames"); json.removeValue(forKey: "hiddenPassword")
        json.removeValue(forKey: "setupCompleted")
        let migrated = try JSONDecoder().decode(SavedLibrary.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.favorites, ["413150"])
        XCTAssertEqual(migrated.hidden, ["2"])
        XCTAssertEqual(migrated.manualGames.first?.name, "Shortcut")
        XCTAssertEqual(migrated.preferences.posterWidth, 199)
        XCTAssertTrue(migrated.removedGames.isEmpty); XCTAssertNil(migrated.hiddenPassword)
        XCTAssertFalse(migrated.setupCompleted)
    }
    func testIncompletePreferencesKeepLibraryAndBoundUnsafeGeometry() throws {
        let data = Data(#"{"preferences":{"steamRoot":"/Volumes/Steam","posterWidth":199,"wallPosterWidth":0,"wallGap":-100,"wallDirection":"obsolete"},"favorites":["413150"],"hidden":["2"]}"#.utf8)
        let saved = try JSONDecoder().decode(SavedLibrary.self, from: data)
        XCTAssertEqual(saved.preferences.steamRoot, "/Volumes/Steam")
        XCTAssertEqual(saved.preferences.posterWidth, 199)
        XCTAssertEqual(saved.preferences.wallPosterWidth, 130)
        XCTAssertEqual(saved.preferences.wallGap, 4)
        XCTAssertEqual(saved.preferences.wallDirection, .diagonal)
        XCTAssertTrue(saved.preferences.onlineMetadata)
        XCTAssertEqual(saved.favorites, ["413150"])
        XCTAssertEqual(saved.hidden, ["2"])
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)), Preferences())
    }
    func testMetadataExpiryUsesTheSamePolicyForCacheAndLibrary() {
        var metadata = GameMetadata(name: "Game", summary: "", genres: [], developers: [], mac: true, windows: false, linux: false)
        XCTAssertFalse(MetadataService.needsRefresh(metadata))
        metadata.fetchedAt = .distantPast
        XCTAssertTrue(MetadataService.needsRefresh(metadata))
        XCTAssertTrue(MetadataService.needsRefresh(nil))
    }
    @MainActor func testSetupPersistsChoicesAndCompletionWithoutResettingLibrary() throws {
        var saved = SavedLibrary()
        saved.favorites = ["413150"]; saved.hidden = ["2"]
        saved.manualGames = [Game(id: "2", name: "Shortcut", addedManually: true)]
        let store = LibraryStore(saved: saved, persistenceEnabled: false)
        XCTAssertTrue(store.showingSetup)
        var draft = store.preferences
        draft.steamRoot = "/Volumes/Games/Steam"; draft.idleEnabled = false
        XCTAssertNotEqual(store.preferences.steamRoot, draft.steamRoot)
        store.finishSetup(draft, rescan: false)
        XCTAssertFalse(store.showingSetup)
        let restored = try JSONDecoder().decode(SavedLibrary.self, from: JSONEncoder().encode(store.saved))
        let relaunched = LibraryStore(saved: restored, persistenceEnabled: false)
        XCTAssertFalse(relaunched.showingSetup)
        XCTAssertEqual(relaunched.preferences, draft)
        XCTAssertEqual(relaunched.saved.favorites, ["413150"])
        XCTAssertEqual(relaunched.saved.hidden, ["2"])
        XCTAssertEqual(relaunched.saved.manualGames.first?.name, "Shortcut")
        relaunched.reopenSetup()
        XCTAssertTrue(relaunched.showingSetup); XCTAssertTrue(relaunched.saved.setupCompleted)
        relaunched.restorePreferences(rescan: false)
        XCTAssertTrue(relaunched.saved.setupCompleted)
    }
    func testPlatformUsesAllDeclaredPlatformsAndLeavesUnknownUnspecified() {
        var game = Game(id: "1", name: "Manual", addedManually: true)
        XCTAssertEqual(game.platformLabel, "平台待确认")
        game.metadata = GameMetadata(name: "Manual", summary: "", genres: [], developers: [], mac: false, windows: true, linux: false)
        XCTAssertEqual(game.platformLabel, "Windows")
        game.metadata?.mac = true; game.metadata?.linux = true
        XCTAssertEqual(game.platformLabel, "macOS / Windows / Linux")
    }
    @MainActor func testSyncedLibraryIncludesPlatformFiltersAndSubtleNonMacBadges() {
        var windows = Game(id: "1", name: "Windows", owned: true)
        windows.metadata = GameMetadata(name: "Windows", summary: "", genres: [], developers: [], mac: false, windows: true, linux: false)
        var linux = Game(id: "2", name: "Linux", owned: true)
        linux.metadata = GameMetadata(name: "Linux", summary: "", genres: [], developers: [], mac: false, windows: false, linux: true)
        var mac = Game(id: "3", name: "Mac", metadata: windows.metadata, owned: true); mac.metadata?.mac = true
        let unknown = Game(id: "4", name: "Unknown", owned: true)
        var saved = SavedLibrary()
        saved.steamAccount = .init(steamID: "76561198000000000", displayName: "Test", syncedAt: .now, games: [windows, linux, mac, unknown])
        let store = LibraryStore(saved: saved, persistenceEnabled: false)
        store.games = saved.steamAccount!.games
        XCTAssertEqual(store.filteredGames.count, 4)
        XCTAssertTrue(store.availableFilters.contains(.windows))
        XCTAssertTrue(store.availableFilters.contains(.linux))
        store.selectFilter(.windows); XCTAssertEqual(Set(store.filteredGames.map(\.id)), ["1", "3"])
        store.selectFilter(.linux); XCTAssertEqual(store.filteredGames.map(\.id), ["2"])
        XCTAssertEqual(windows.nonMacPlatforms, [.windows])
        XCTAssertEqual(linux.nonMacPlatforms, [.linux])
        XCTAssertTrue(mac.nonMacPlatforms.isEmpty)
        XCTAssertTrue(unknown.nonMacPlatforms.isEmpty)
        store.removeAccountCache()
        XCTAssertFalse(store.availableFilters.contains(.windows))
        XCTAssertFalse(store.availableFilters.contains(.linux))
        XCTAssertEqual(store.filter, .all)
    }
    func testPasswordIsSaltedAndVerifiesUnicodeWithoutSavingPlaintext() throws {
        let password = "游戏🔒123"
        let first = try HiddenPassword.create(password), second = try HiddenPassword.create(password)
        XCTAssertNotEqual(first.salt, second.salt); XCTAssertNotEqual(first.digest, second.digest)
        XCTAssertTrue(HiddenPassword.verify(password, record: first))
        XCTAssertFalse(HiddenPassword.verify("wrong", record: first))
        XCTAssertFalse(HiddenPassword.verify("", record: first))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(first), as: UTF8.self).contains(password))
    }
    @MainActor func testHiddenGateExcludesOtherSurfacesAndRelocks() async throws {
        let hidden = Game(id: "1", name: "Hidden", installed: true)
        let normal = Game(id: "2", name: "Normal", installed: true)
        var saved = SavedLibrary(); saved.hidden = ["1"]; saved.favorites = ["1", "2"]
        saved.hiddenPassword = try HiddenPassword.create("pass")
        let store = LibraryStore(saved: saved, persistenceEnabled: false)
        store.games = [hidden, normal]; store.cachedPosterIDs = ["1", "2"]
        XCTAssertEqual(store.visibleGames.map(\.id), ["2"])
        XCTAssertEqual(store.favoriteGames.map(\.id), ["2"])
        XCTAssertEqual(store.wallGames.map(\.id), ["2"])
        store.selectFilter(.hidden); store.requestHiddenDisplay()
        XCTAssertTrue(store.showingUnlock); XCTAssertTrue(store.filteredGames.isEmpty)
        let wrong = await store.unlockHidden(password: "wrong"); XCTAssertFalse(wrong)
        let correct = await store.unlockHidden(password: "pass"); XCTAssertTrue(correct)
        XCTAssertEqual(store.filteredGames.map(\.id), ["1"])
        store.navigate(.home); XCTAssertFalse(store.hiddenUnlocked)
        store.selectFilter(.hidden); XCTAssertTrue(store.filteredGames.isEmpty)
        store.restorePreferences(rescan: false)
        XCTAssertNotNil(store.saved.hiddenPassword); XCTAssertEqual(store.saved.hidden, ["1"])
        XCTAssertEqual(store.saved.favorites, ["1", "2"])
    }
    @MainActor func testUnprotectedHiddenShowWorksEvenWhenEmpty() {
        let store = LibraryStore(saved: SavedLibrary(), persistenceEnabled: false)
        store.selectFilter(.hidden); store.requestHiddenDisplay()
        XCTAssertTrue(store.hiddenUnlocked); XCTAssertTrue(store.filteredGames.isEmpty)
        store.lockHidden(); XCTAssertFalse(store.hiddenUnlocked)
    }
    @MainActor func testArchiveRestorePreservesEntryAndDoesNotDeleteSource() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sh")
        try "#!/bin/sh\nprintf '%s' test\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = LibraryStore(saved: SavedLibrary(), persistenceEnabled: false)
        XCTAssertTrue(store.addLocal(url: file))
        let game = try XCTUnwrap(store.games.first)
        store.saved.favorites.insert(game.id)
        store.removeManual(game)
        XCTAssertTrue(store.games.isEmpty); XCTAssertEqual(store.recoverableGames, [game])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        store.restoreManual(game)
        XCTAssertEqual(store.games, [game]); XCTAssertTrue(store.saved.removedGames.isEmpty)
        XCTAssertTrue(store.saved.favorites.contains(game.id))
    }
    func testLocalLaunchArgumentsArePassedLiterallyAndRespectShebang() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + " a.command")
        try "#!/bin/sh\nprintf '%s\\n' \"$1\"\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let argument = "two words; $(echo must-not-execute)"
        let target = LocalTarget(path: file.path, kind: .command, arguments: [argument])
        let plan = try XCTUnwrap(LocalLaunchPlan.make(target))
        XCTAssertEqual(plan.executable, "/bin/sh"); XCTAssertEqual(plan.arguments, [file.path, argument])
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: plan.executable); process.arguments = plan.arguments
        process.standardOutput = pipe; try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), argument + "\n")
        XCTAssertEqual(LocalLaunchPlan.make(.init(path: "/tmp/a b.jar", kind: .jar))?.arguments, ["-jar", "/tmp/a b.jar"])
        XCTAssertNil(LocalLaunchPlan.make(.init(path: "/Applications/Test.app", kind: .application)))
    }
}

final class SteamAccountTests: XCTestCase {
    func testOwnedLibraryDecodesNamesPlaytimeAndRejectsIncompleteResponses() throws {
        let raw = #"{"response":{"game_count":2,"games":[{"appid":413150,"name":"Stardew Valley","playtime_forever":123,"rtime_last_played":1700000000},{"appid":570,"name":"Dota 2"}]}}"#
        let response = try JSONDecoder().decode(SteamOwnedGamesResponse.self, from: Data(raw.utf8))
        let snapshot = try response.snapshot(steamID: "76561198000000000", displayName: "Test")
        XCTAssertEqual(snapshot.games.count, 2); XCTAssertEqual(snapshot.games.first?.playtimeMinutes, 123)
        XCTAssertEqual(snapshot.games.first?.lastPlayed, Date(timeIntervalSince1970: 1700000000))
        XCTAssertTrue(snapshot.games.allSatisfy { $0.owned == true && !$0.installed })
        for invalid in [#"{"response":{}}"#, #"{"response":{"game_count":2,"games":[]}}"#, #"{"response":{"game_count":1,"games":[{"appid":0}]}}"#] {
            let decoded = try JSONDecoder().decode(SteamOwnedGamesResponse.self, from: Data(invalid.utf8))
            XCTAssertThrowsError(try decoded.snapshot(steamID: "76561198000000000", displayName: "Test"))
        }
        let empty = try JSONDecoder().decode(SteamOwnedGamesResponse.self, from: Data(#"{"response":{"game_count":0}}"#.utf8))
        XCTAssertTrue(try empty.snapshot(steamID: "76561198000000000", displayName: "Test").games.isEmpty)
    }
    func testLibraryMergeDeduplicatesAndInstallationComesOnlyFromLocalScan() {
        let local = Game(id: "413150", name: "Stardew", installPath: "/tmp/game", installed: true, playtimeMinutes: 500)
        var owned = Game(id: "413150", name: "Stardew", playtimeMinutes: 123); owned.owned = true
        var remote = Game(id: "570", name: "Dota 2", installPath: "/stale/path", installed: true); remote.owned = true
        let manual = Game(id: "7", name: "Shortcut", addedManually: true)
        let result = LibraryMerger.merge(installed: [local], account: [owned, remote], manual: [manual], previous: [])
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[0].installed); XCTAssertEqual(result[0].owned, true)
        XCTAssertEqual(result[0].playtimeMinutes, 123)
        XCTAssertFalse(result[1].installed); XCTAssertNil(result[1].installPath)
        XCTAssertEqual(result[2].addedManually, true)
        let signedOut = LibraryMerger.merge(installed: result, account: [], manual: [manual], previous: result)
        XCTAssertEqual(signedOut.map(\.id), ["413150", "7"]); XCTAssertNil(signedOut[0].owned)
    }
    @MainActor func testAccountSnapshotSurvivesLocalPersistenceWithoutSecrets() throws {
        var saved = SavedLibrary()
        saved.steamAccount = .init(steamID: "76561198000000000", displayName: "Test", syncedAt: .now,
                                  games: [Game(id: "570", name: "Dota 2", owned: true)])
        let bytes = try JSONEncoder().encode(saved)
        let json = String(decoding: bytes, as: UTF8.self)
        for secret in ["access_token", "webapi_token", "steamLoginSecure", "sessionid"] { XCTAssertFalse(json.contains(secret)) }
        let restored = try JSONDecoder().decode(SavedLibrary.self, from: bytes)
        XCTAssertEqual(restored.steamAccount, saved.steamAccount)
        let store = LibraryStore(saved: restored, persistenceEnabled: false)
        XCTAssertTrue(store.availableFilters.contains(.installed)); XCTAssertTrue(store.availableFilters.contains(.owned))
        store.removeAccountCache()
        XCTAssertFalse(store.availableFilters.contains(.installed)); XCTAssertFalse(store.availableFilters.contains(.owned))
    }
    @MainActor func testOfficialNavigationRejectsLookalikeDomainsAndInsecureURLs() {
        for url in ["https://store.steampowered.com/login", "https://login.steampowered.com/jwt/finalizelogin", "https://steamcommunity.com/my"] {
            XCTAssertTrue(SteamAccountSession.isOfficial(URL(string: url)!))
        }
        for url in ["https://steampowered.com.attacker.test/login", "http://store.steampowered.com/login", "https://steamcommunity.com.attacker.test", "javascript:alert(1)"] {
            XCTAssertFalse(SteamAccountSession.isOfficial(URL(string: url)!))
        }
    }
}
