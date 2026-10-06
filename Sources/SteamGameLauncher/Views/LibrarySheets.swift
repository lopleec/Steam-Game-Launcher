import SwiftUI

struct AddGameSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var appID = ""
    @State private var name = ""
    private var parsedID: String {
        let value = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        if SteamLink.validAppID(value) { return value }
        if let url = URL(string: value), ["store.steampowered.com", "steamcommunity.com"].contains(url.host ?? ""),
           url.pathComponents.count >= 3, url.pathComponents[1] == "app" { return url.pathComponents[2] }
        if let url = URL(string: value), url.scheme == "steam", ["rungameid", "store"].contains(url.host ?? "") { return url.lastPathComponent }
        return ""
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Image(systemName: "link").font(.system(size: 22)); Text("添加 Steam 快捷入口").font(.system(size: 22, weight: .semibold)) }
            Text("输入 App ID 或粘贴 Steam 商店链接。入口不会下载游戏，也不会验证账号所有权。")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 9) {
                Text("APP ID / 商店链接").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                TextField("例如 413150", text: $appID).textFieldStyle(.roundedBorder)
                TextField("游戏名称（留空时从 Steam 获取）", text: $name).textFieldStyle(.roundedBorder)
            }
            HStack {
                if !parsedID.isEmpty { Text("App ID  \(parsedID)").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button("添加入口") { if store.addManual(id: parsedID, name: name) { dismiss() } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: []).disabled(!SteamLink.validAppID(parsedID))
            }
        }.padding(30).frame(width: 490)
    }
}

struct CollectionsSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("你的合集").font(.system(size: 24, weight: .semibold))
            Text("按你自己的方式整理游戏。在游戏右键菜单中加入合集。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                TextField("新合集名称", text: $name).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("创建", action: add).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.saved.collections) { collection in
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack").foregroundStyle(.secondary)
                            TextField("合集名称", text: Binding(get: { store.saved.collections.first { $0.id == collection.id }?.name ?? "" }, set: { value in
                                if let index = store.saved.collections.firstIndex(where: { $0.id == collection.id }) { store.saved.collections[index].name = value }
                            })).textFieldStyle(.plain)
                            Text("\(collection.gameIDs.count) 款").font(.system(size: 11)).foregroundStyle(.secondary)
                            Button { store.saved.collections.removeAll { $0.id == collection.id } } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }.buttonStyle(.plain).help("移除合集，保留游戏")
                        }.padding(13).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if store.saved.collections.isEmpty { Text("为独立游戏、周末冒险，或者还没通关的故事建一个合集。").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 30) }
                }
            }.frame(height: 210)
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.return, modifiers: []) }
        }.padding(30).frame(width: 490)
    }
    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.saved.collections.append(GameCollection(name: trimmed)); name = ""
    }
}

struct UnlockHiddenSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("显示隐藏的游戏", systemImage: "lock").font(.system(size: 22, weight: .semibold))
            Text("输入密码解锁这个分类。").font(.system(size: 13)).foregroundStyle(.secondary)
            SecureField("密码", text: $password).textFieldStyle(.roundedBorder).focused($focused).onSubmit(unlock)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消", role: .cancel) { password = ""; dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button("显示", action: unlock).buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: []).disabled(busy || password.isEmpty)
            }
        }.padding(30).frame(width: 420).onAppear { focused = true }
    }
    private func unlock() {
        guard !busy, !password.isEmpty else { return }
        busy = true; error = nil
        Task {
            let valid = await store.unlockHidden(password: password)
            busy = false; password = ""
            if valid { dismiss() } else { error = "密码不正确，或解锁请求已过期。"; focused = true }
        }
    }
}

struct HiddenPasswordSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var busy = false
    private var hasPassword: Bool { store.saved.hiddenPassword != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(hasPassword ? "管理隐藏分类密码" : "设置隐藏分类密码", systemImage: "lock.shield").font(.system(size: 22, weight: .semibold))
            Text("密码用于解锁本应用内的隐藏分类。离开分类或切到其他应用后会重新锁定。")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                if hasPassword { SecureField("当前密码", text: $current).textFieldStyle(.roundedBorder) }
                SecureField("新密码", text: $password).textFieldStyle(.roundedBorder)
                SecureField("再次输入新密码", text: $confirmation).textFieldStyle(.roundedBorder)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                if hasPassword { Button("关闭密码") { save(remove: true) }.disabled(busy || current.isEmpty) }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button("保存") { save(remove: false) }.buttonStyle(.borderedProminent)
                    .disabled(busy || password.isEmpty || password != confirmation || (hasPassword && current.isEmpty))
            }
        }.padding(30).frame(width: 490)
    }
    private func save(remove: Bool) {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            let valid = await store.configurePassword(current: current, new: remove ? nil : password)
            busy = false; current = ""; password = ""; confirmation = ""
            if valid { store.toast(remove ? "已关闭隐藏分类密码" : "已保存隐藏分类密码"); dismiss() }
            else { error = "当前密码不正确，或密码未能保存。" }
        }
    }
}

struct RecoverEntriesSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("恢复入口").font(.system(size: 24, weight: .semibold))
            Text("移除入口会保留原文件，以及入口的收藏、原画和合集记录。").font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.recoverableGames) { game in
                        HStack(spacing: 14) {
                            GameArtwork(game: game).frame(width: 40, height: 60).clipShape(RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(game.name).font(.system(size: 13, weight: .medium))
                                Text(game.isSteam ? "Steam App \(game.id)" : game.localTarget?.kind.label ?? "本地入口").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("恢复") { store.restoreManual(game) }.buttonStyle(.bordered)
                        }.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if store.recoverableGames.isEmpty { Text("暂无可恢复的入口").foregroundStyle(.secondary).padding(.vertical, 65) }
                }
            }.frame(height: 280)
            Text("隐藏的入口仅在解锁隐藏分类后显示。").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.escape, modifiers: []) }
        }.padding(30).frame(width: 540)
    }
}

struct LocalArgumentsSheet: View {
    let game: Game
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var arguments = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("启动参数").font(.system(size: 24, weight: .semibold))
            Text(game.name).font(.system(size: 13, weight: .medium))
            Text("每行一个参数。带空格的参数保持原样，无需添加引号。").font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $arguments).font(.system(size: 12, design: .monospaced)).frame(height: 150)
                .padding(8).background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            HStack { Spacer(); Button("取消", role: .cancel) { dismiss() }; Button("保存") {
                store.updateLocalArguments(game, arguments: arguments.components(separatedBy: .newlines).filter { !$0.isEmpty }); dismiss()
            }.buttonStyle(.borderedProminent) }
        }.padding(30).frame(width: 490).onAppear { arguments = game.localTarget?.arguments.joined(separator: "\n") ?? "" }
    }
}
