import AppKit
import WebKit
import Observation

/// Steam credentials stay in this app's persistent WebKit website store.
/// Only public account identity and owned-game data enter library.json.
@Observable @MainActor final class SteamAccountSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var isSyncing = false
    var isLoading = false
    var status = "在 Steam 官方页面登录后同步游戏库。"
    var pageHost = "store.steampowered.com"
    var syncError: String?
    @ObservationIgnored weak var store: LibraryStore?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }
    static func isOfficial(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "steampowered.com" || host.hasSuffix(".steampowered.com") || host == "steamcommunity.com" || host.hasSuffix(".steamcommunity.com")
    }
    func beginLogin() {
        cancelSync(); syncError = nil; status = "请在 Steam 官方页面登录，支持 Steam Guard 和扫码。"
        webView.load(URLRequest(url: URL(string: "https://store.steampowered.com/login/?redir=points%2Fshop%2F&redir_ssl=1")!))
    }
    func refresh() {
        guard !isSyncing else { return }
        generation += 1; pendingRefresh = true; isSyncing = true; syncError = nil; status = "正在连接 Steam…"
        webView.load(URLRequest(url: URL(string: "https://store.steampowered.com/points/shop/?l=schinese")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
        let current = generation
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(40))
            if !Task.isCancelled, generation == current, pendingRefresh {
                fail(SteamSyncError.unavailable)
            }
        }
    }
    func cancelSync() {
        generation += 1; syncTask?.cancel(); syncTask = nil; timeoutTask?.cancel(); pendingRefresh = false; isSyncing = false
    }
    func logout() async {
        cancelSync(); webView.stopLoading()
        // This website store belongs to this app; other browsers and the Steam client are untouched.
        let dataStore = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
        store?.removeAccountCache(); syncError = nil; status = "已退出 Steam，账号游戏缓存已移除。"
        webView.loadHTMLString("", baseURL: nil)
    }
    func syncFromCurrentPage() {
        guard !isSyncing else { return }
        if webView.url?.host != "store.steampowered.com" || webView.url?.path.contains("/login") == true { refresh(); return }
        generation += 1; isSyncing = true; syncError = nil
        synchronize(generation: generation)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true; pageHost = webView.url?.host ?? "store.steampowered.com"
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false; pageHost = webView.url?.host ?? "store.steampowered.com"
        guard webView.url?.host == "store.steampowered.com", webView.url?.path.hasPrefix("/points/shop") == true else { return }
        if !isSyncing { generation += 1; isSyncing = true }
        pendingRefresh = false; timeoutTask?.cancel()
        synchronize(generation: generation)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    private func navigationFailed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        isLoading = false; fail(SteamSyncError.unavailable)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if Self.isOfficial(url) || url.absoluteString == "about:blank" { decisionHandler(.allow) }
        else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated, url.scheme == "https" { NSWorkspace.shared.open(url) }
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, Self.isOfficial(url) { webView.load(navigationAction.request) }
        return nil
    }
    private func synchronize(generation current: Int) {
        guard syncTask == nil else { return }
        status = "正在同步账号游戏库…"
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == current { syncTask = nil } }
            do {
                let result = try await webView.callAsyncJavaScript(Self.ticketScript, arguments: [:], in: nil, contentWorld: .page)
                guard generation == current, !Task.isCancelled else { return }
                guard let ticket = result as? [String: Any], let token = ticket["token"] as? String, !token.isEmpty,
                      let steamID = ticket["steamID"] as? String, steamID.count == 17, steamID.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                    throw SteamSyncError.signInRequired
                }
                let name = ticket["name"] as? String ?? "Steam"
                let snapshot = try await Self.fetchOwnedGames(token: token, steamID: steamID, name: name)
                guard generation == current, !Task.isCancelled else { return }
                store?.applyAccountSnapshot(snapshot)
                isSyncing = false; syncError = nil
                status = "已同步 \(snapshot.games.count) 款游戏 · \(snapshot.syncedAt.formatted(date: .omitted, time: .shortened))"
                store?.showingSteamLogin = false
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                fail(error is SteamSyncError ? error : SteamSyncError.unavailable)
                if case SteamSyncError.signInRequired = error {
                    store?.showingSteamLogin = true
                    webView.load(URLRequest(url: URL(string: "https://store.steampowered.com/login/?redir=points%2Fshop%2F&redir_ssl=1")!))
                }
            }
        }
    }
    private func fail(_ error: Error) {
        pendingRefresh = false; isSyncing = false; timeoutTask?.cancel()
        syncError = error.localizedDescription; status = error.localizedDescription
    }
    private static func fetchOwnedGames(token: String, steamID: String, name: String) async throws -> SteamAccountSnapshot {
        var components = URLComponents(string: "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/")!
        components.queryItems = ["access_token": token, "steamid": steamID, "include_appinfo": "1", "include_played_free_games": "1", "include_free_sub": "1", "skip_unvetted_apps": "0", "language": "schinese", "format": "json"].map { .init(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!); request.timeoutInterval = 30
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: SteamAPITransport(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SteamSyncError.unavailable }
        if http.statusCode == 401 || http.statusCode == 403 { throw SteamSyncError.signInRequired }
        guard http.statusCode == 200, data.count < 25_000_000 else { throw SteamSyncError.unavailable }
        return try JSONDecoder().decode(SteamOwnedGamesResponse.self, from: data).snapshot(steamID: steamID, displayName: name)
    }
    private static let ticketScript = #"""
    if (location.protocol !== 'https:' || location.hostname !== 'store.steampowered.com') return null;
    const element = document.getElementById('application_config');
    let user = {};
    try { user = JSON.parse(element?.dataset.userinfo || '{}'); } catch (_) {}
    const response = await fetch('/pointssummary/ajaxgetasyncconfig', {credentials: 'include', cache: 'no-store', signal: AbortSignal.timeout(20000)});
    if (!response.ok) return null;
    const config = await response.json();
    let token = config?.data?.webapi_token || user.webapi_token || '';
    if (!token) {
        try { token = JSON.parse(element?.dataset.loyaltystore || '{}').webapi_token || ''; } catch (_) {}
    }
    let steamID = String(user.steamid || window.g_steamID || '');
    if (!/^\d{17}$/.test(steamID) && token.split('.').length === 3) {
        try {
            const base64 = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
            steamID = String(JSON.parse(atob(base64)).sub || '');
        } catch (_) {}
    }
    const name = document.querySelector('#account_pulldown')?.textContent?.trim() || 'Steam';
    // Do not return passwords, cookies, login forms or Steam Guard codes.
    return {token, steamID, name};
    """#
}

private final class SteamAPITransport: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "api.steampowered.com" ? request : nil)
    }
}
