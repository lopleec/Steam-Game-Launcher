import SwiftUI
import WebKit

struct SteamLoginView: View {
    @Environment(SteamAccountSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("登录 Steam").font(.system(size: 16, weight: .semibold))
                    Text("https://\(session.pageHost)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                if session.isSyncing || session.isLoading { ProgressView().controlSize(.small) }
                Button("同步游戏库") { session.syncFromCurrentPage() }.disabled(session.isSyncing || session.isLoading)
                Button("关闭") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
            }.padding(18)
            Divider()
            SteamWebView(webView: session.webView)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.status).font(.system(size: 12)).foregroundStyle(session.syncError == nil ? Color.secondary : Color.red)
                    Text("会话和游戏库保存在本机。登录与验证码由 Steam 官方页面处理。").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新登录") { session.beginLogin() }.controlSize(.small).disabled(session.isSyncing)
            }.padding(16)
        }.frame(width: 900, height: 620)
    }
}

private struct SteamWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
