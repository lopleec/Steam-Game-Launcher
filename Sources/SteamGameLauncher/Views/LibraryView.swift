import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    private var isHidden: Bool { store.filter == .hidden }
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR COLLECTION").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(.secondary)
                        Text(title).font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                    }
                    Spacer()
                    if !isHidden || store.hiddenUnlocked {
                        Text("\(store.filteredGames.count) 个入口").font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 6)
                    }
                    Menu {
                        Button("打开 Steam 游戏库") { store.openSteam(.library) }
                        Button("添加本地应用或文件…") { store.chooseLocalEntries() }
                        Button("添加 App ID…") { store.showingAddGame = true }
                        Button("恢复入口…") { store.showingRemoved = true }
                        Button("管理合集…") { store.showingCollections = true }
                    } label: { Image(systemName: "plus").frame(width: 40, height: 40).contentShape(Rectangle()) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 40).help("添加入口")
                }
                HStack(spacing: 4) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                    ForEach(store.availableFilters) { filter in
                        Button { store.selectFilter(filter) } label: {
                            VStack(spacing: 0) {
                                Text(filter.rawValue).font(.system(size: 13, weight: store.filter == filter ? .semibold : .regular))
                                    .foregroundStyle(store.filter == filter ? .primary : .secondary)
                                    .padding(.horizontal, 10).frame(height: 42)
                                Capsule().fill(store.filter == filter ? Color.primary : .clear).frame(height: 2)
                            }.fixedSize(horizontal: true, vertical: false).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                        }
                    }.scrollIndicators(.hidden)
                    Spacer(minLength: 8)
                    if isHidden {
                        Button("显示") { store.requestHiddenDisplay() }.buttonStyle(.bordered).controlSize(.large)
                        if store.hiddenUnlocked {
                            Button { store.lockHidden() } label: { Image(systemName: "lock").frame(width: 36, height: 36).contentShape(Rectangle()) }
                                .buttonStyle(.plain).help("锁定隐藏分类")
                        }
                    } else {
                        Menu {
                            Picker("排序方式", selection: $store.sort) { ForEach(GameSort.allCases) { Text($0.rawValue).tag($0) } }
                        } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 40, height: 40).contentShape(Rectangle()) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 40).help("排序：\(store.sort.rawValue)")
                        if !store.saved.collections.isEmpty {
                            Menu {
                                Button("全部合集") { store.collectionID = nil }
                                ForEach(store.saved.collections) { collection in Button(collection.name) { store.collectionID = collection.id } }
                            } label: { Image(systemName: "square.stack").frame(width: 40, height: 40).contentShape(Rectangle()) }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 40)
                        }
                    }
                }
            }.padding(.horizontal, 42).padding(.top, 27).padding(.bottom, 4)
            Divider().opacity(0.4).padding(.horizontal, 42)
            if isHidden && !store.hiddenUnlocked {
                ContentUnavailableView {
                    Label("隐藏的游戏", systemImage: store.saved.hiddenPassword == nil ? "eye.slash" : "lock")
                } description: {
                    Text(store.saved.hiddenPassword == nil ? "点击“显示”查看隐藏的入口。" : "输入密码后查看隐藏的入口。")
                } actions: {
                    Button("显示") { store.requestHiddenDisplay() }.controlSize(.large).buttonStyle(.borderedProminent)
                }.frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: store.preferences.posterWidth, maximum: store.preferences.posterWidth), spacing: 24, alignment: .top)], alignment: .leading, spacing: 31) {
                        ForEach(store.filteredGames) { game in PosterCard(game: game, width: store.preferences.posterWidth) }
                        if !isHidden { AddLibraryCard(width: store.preferences.posterWidth) }
                    }.padding(.horizontal, 42).padding(.top, 27).padding(.bottom, 35)
                    if store.filteredGames.isEmpty {
                        Text(isHidden ? "没有隐藏的入口" : store.search.isEmpty ? "从 Steam 或本地文件添加你的下一个入口。" : "没有找到匹配的入口")
                            .font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
                    }
                }
            }
        }
    }
    private var title: String {
        if isHidden { return "隐藏的游戏" }
        if let collectionID = store.collectionID, let collection = store.saved.collections.first(where: { $0.id == collectionID }) { return collection.name }
        return store.destination == .favorites ? "收藏" : "游戏库"
    }
}

struct AddLibraryCard: View {
    var width: CGFloat
    @Environment(LibraryStore.self) private var store
    @State private var hovered = false
    var body: some View {
        Button { store.openSteam(.library) } label: {
            VStack(alignment: .leading, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(hovered ? 0.055 : 0.025))
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(hovered ? 0.3 : 0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    VStack(spacing: 17) {
                        Image(systemName: "plus").font(.system(size: 30, weight: .ultraLight)).frame(width: 62, height: 62)
                            .background(.primary.opacity(0.04), in: Circle())
                        Text("下一段旅程").font(.system(size: 12, weight: .medium))
                    }.foregroundStyle(.secondary)
                }.frame(width: width, height: width * 1.5)
                Text("Steam 游戏库").font(.system(size: 13, weight: .medium))
                Label("在 Steam 中浏览", systemImage: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(width: width, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }.help("打开 Steam Library")
    }
}
