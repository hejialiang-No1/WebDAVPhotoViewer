import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var imageCache = ImageCache()
    @StateObject private var sizeStore = ImageSizeStore()
    @State private var selectedItem: WebDAVItem?
    @State private var searchText = ""
    @State private var showSettings = false
    /// 显示列数：1 = 单列，2 = 双列瀑布流
    @AppStorage("wd_columns") private var columns = 2

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(session.currentTitle)
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar { toolbarContent }
                .searchable(text: $searchText, prompt: "搜索图片")
                .refreshable { await session.reload() }
        }
        .sheet(item: $selectedItem) { item in
            if let client = session.client {
                PhotoDetailView(item: item, client: client, cache: imageCache,
                                allItems: session.filteredImages(search: searchText))
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: 主体
    private var content: some View {
        GeometryReader { geo in
            let cols = max(1, min(columns, 2))
            let cw = cols == 1 ? (geo.size.width - 16) : (geo.size.width - 20) / 2
            let images = session.filteredImages(search: searchText)
            let heights = images.map { cw * (sizeStore.aspects[$0.id] ?? 1.3) }
            let frameWidth = cw * CGFloat(cols) + 4 * CGFloat(cols - 1)

            ScrollView {
                VStack(spacing: 8) {
                    if !session.scanAllFolders { foldersSection }
                    MasonryLayout(columns: cols, spacing: 4, columnWidth: cw, heights: heights) {
                        ForEach(images) { item in
                            PhotoCell(item: item, client: session.client!, cache: imageCache, sizeStore: sizeStore)
                                .onTapGesture { selectedItem = item }
                        }
                    }
                    .frame(width: frameWidth)

                    if images.isEmpty && !session.isLoading {
                        emptyView
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(backgroundGradient)
            .overlay {
                if session.isLoading && images.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        if session.scanAllFolders {
                            Text("正在扫描所有文件夹…")
                                .font(.subheadline)
                        } else {
                            Text("加载中…")
                        }
                    }
                    .padding(24)
                    .glassCard(cornerRadius: 18)
                }
            }
        }
    }

    @ViewBuilder
    private var foldersSection: some View {
        if !session.folders.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(session.folders) { folder in
                        Button { session.navigate(to: folder) } label: {
                            Label(folder.name, systemImage: "folder.fill")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .glassCard(cornerRadius: 14)
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(session.errorMessage ?? "该目录下没有图片")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: 工具栏
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if session.pathStack.count > 1 {
                Button { session.goBack() } label: { Image(systemName: "chevron.left") }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 2) {
                // 单 / 双列切换
                Button {
                    columns = (columns == 2 ? 1 : 2)
                } label: {
                    Image(systemName: columns == 2 ? "square.split.2x2" : "rectangle")
                }
                .help(columns == 2 ? "切换为单列" : "切换为双列")
                // 扫描所有子文件夹的照片
                Button {
                    Task { await session.toggleScanAll() }
                } label: {
                    Image(systemName: session.scanAllFolders ? "photo.stack" : "photo.stack")
                        .symbolVariant(session.scanAllFolders ? .fill : .none)
                }
                .help(session.scanAllFolders ? "退出全部照片扫描" : "扫描所有子文件夹的照片")
                Menu { sortMenu } label: { Image(systemName: "arrow.up.arrow.down") }
                Menu { themeMenu } label: { Image(systemName: session.themeMode.systemImage) }
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
    }

    private var sortMenu: some View {
        Section("排序方式") {
            ForEach(SortOption.allCases) { opt in
                Button { session.sortOption = opt } label: {
                    Label(opt.label, systemImage: opt.systemImage)
                }
            }
        }
    }

    private var themeMenu: some View {
        Section("主题") {
            ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                Button { session.themeMode = mode } label: {
                    Label(mode.label, systemImage: mode.systemImage)
                }
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)],
            startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}
