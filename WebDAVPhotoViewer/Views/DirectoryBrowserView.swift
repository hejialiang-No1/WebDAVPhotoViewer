import SwiftUI

/// 登录后选择起始目录：浏览服务器上的文件夹，选定后进入图库
struct DirectoryBrowserView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    /// WebDAV 相对路径栈（空字符串 = 根）
    @State private var pathStack: [String] = [""]
    @State private var folders: [WebDAVItem] = []
    @State private var isLoading = false
    @State private var error: String?

    private var currentPath: String { pathStack.last ?? "" }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("选择起始目录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        if pathStack.count > 1 {
                            Button { goUp() } label: { Image(systemName: "chevron.left") }
                        } else {
                            Button("从根目录开始") { confirm(path: "") }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("选择此目录") { confirm(path: currentPath) }
                            .fontWeight(.semibold)
                    }
                }
                .task { await loadCurrent() }
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                // 当前路径提示
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(.secondary)
                    Text(currentPath.isEmpty ? "/" : currentPath)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)

                Divider()

                if isLoading && folders.isEmpty {
                    Spacer()
                    ProgressView("加载中…").padding()
                    Spacer()
                } else if folders.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "folder").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text(currentPath.isEmpty ? "根目录下没有子文件夹" : "此目录下没有子文件夹")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(folders) { folder in
                            Button { open(folder) } label: {
                                Label(folder.name, systemImage: "folder.fill")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .alert("出错", isPresented: .constant(error != nil)) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func open(_ folder: WebDAVItem) {
        let next = currentPath.isEmpty ? folder.name : currentPath + "/" + folder.name
        pathStack.append(next)
        Task { await loadCurrent() }
    }

    private func goUp() {
        guard pathStack.count > 1 else { return }
        pathStack.removeLast()
        Task { await loadCurrent() }
    }

    private func loadCurrent() async {
        guard let client = session.client else { return }
        isLoading = true
        error = nil
        do {
            let items = try await client.listFiles(at: currentPath)
            await MainActor.run {
                self.folders = items.filter { $0.isDirectory }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = (error as? WebDAVError)?.errorDescription ?? error.localizedDescription
                self.folders = []
                self.isLoading = false
            }
        }
    }

    private func confirm(path: String) {
        session.enter(startPath: path)
        dismiss()
    }
}
