import Foundation
import SwiftUI
import Combine

/// 全局会话状态：登录、目录、排序、主题、导航
@MainActor final class SessionStore: ObservableObject {
    @AppStorage("wd_server") private var storedServer = ""
    @AppStorage("wd_username") private var storedUsername = ""
    private let keychain = KeychainHelper.shared

    @Published var isLoggedIn = false
    @Published var items: [WebDAVItem] = []
    @Published var pathStack: [String] = []
    @Published var sortOption: SortOption = .nameAsc
    @Published var themeMode: ThemeMode = .system
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var client: WebDAVClient?

    /// 是否开启「扫描所有子文件夹的照片」（递归收集全部图片到同一视图）
    @Published var scanAllFolders = false
    /// 递归扫描得到的全部照片（scanAllFolders 为 true 时生效）
    @Published var allPhotos: [WebDAVItem] = []

    var currentPath: String { pathStack.last ?? "" }
    var currentTitle: String {
        if scanAllFolders { return "全部照片" }
        guard let last = pathStack.last, !last.isEmpty else { return "照片" }
        let comp = (last as NSString).pathComponents.filter { !$0.isEmpty }
        return comp.last ?? "照片"
    }

    var serverDisplay: String? { storedServer.nilIfEmpty }

    init() {
        // 尝试静默恢复上次登录
        if let server = storedServer.nilIfEmpty,
           let password = keychain.read("wd_password"),
           !password.isEmpty {
            Task { await login(server: server, username: storedUsername, password: password, silent: true) }
        }
    }

    // MARK: 登录 / 登出

    /// 仅验证连接并保存凭据/客户端，不进入图库（用于登录后先选起始目录）
    @discardableResult
    func connect(server: String, username: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        let url = normalizeServer(server)
        let newClient = WebDAVClient(baseURL: url, username: username, password: password)
        do {
            _ = try await newClient.listFiles(at: "")
            self.client = newClient
            self.storedServer = server
            self.storedUsername = username
            self.keychain.save(password, for: "wd_password")
            self.isLoading = false
            return true
        } catch {
            self.errorMessage = (error as? WebDAVError)?.errorDescription ?? error.localizedDescription
            self.isLoading = false
            return false
        }
    }

    /// 进入图库（连接成功后调用），可选起始目录；默认从根目录开始
    func enter(startPath: String = "") {
        guard let client = client else { return }
        let url = normalizeServer(storedServer)
        let path = startPath.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        Task {
            if path.isEmpty {
                self.items = (try? await client.listFiles(at: "")) ?? []
                self.pathStack = [url.absoluteString]
            } else {
                let startURL = url.appendingPathComponent(path)
                do {
                    self.items = try await client.listFiles(at: path)
                    self.pathStack = [startURL.absoluteString]
                } catch {
                    self.items = (try? await client.listFiles(at: "")) ?? []
                    self.pathStack = [url.absoluteString]
                    await MainActor.run { self.errorMessage = "起始目录不存在，已打开根目录" }
                }
            }
            self.isLoggedIn = true
            self.isLoading = false
        }
    }

    /// 静默恢复 / 直接登录（含起始目录）使用
    func login(server: String, username: String, password: String,
               startPath: String = "", silent: Bool = false) async {
        guard !silent || !isLoggedIn else { return }
        let ok = await connect(server: server, username: username, password: password)
        if ok { enter(startPath: startPath) }
    }

    func logout() {
        storedServer = ""
        storedUsername = ""
        keychain.delete("wd_password")
        client = nil
        items = []
        pathStack = []
        allPhotos = []
        scanAllFolders = false
        isLoggedIn = false
        errorMessage = nil
    }

    func reload() async {
        guard let client, !currentPath.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            items = try await client.listFiles(at: currentPath)
            isLoading = false
        } catch {
            errorMessage = (error as? WebDAVError)?.errorDescription ?? error.localizedDescription
            isLoading = false
        }
    }

    // MARK: 扫描全部子文件夹的照片
    func toggleScanAll() async {
        scanAllFolders.toggle()
        if scanAllFolders {
            await scanAll()
        } else {
            allPhotos = []
            await reload()   // 退出「全部照片」后回到当前文件夹
        }
    }

    func scanAll() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        do {
            allPhotos = try await client.scanAllPhotos(at: currentPath)
            isLoading = false
        } catch {
            errorMessage = (error as? WebDAVError)?.errorDescription ?? error.localizedDescription
            scanAllFolders = false
            allPhotos = []
            isLoading = false
        }
    }

    // MARK: 导航
    func navigate(to folder: WebDAVItem) {
        guard folder.isDirectory else { return }
        // 进入子文件夹即退出「全部照片」模式
        scanAllFolders = false
        allPhotos = []
        pathStack.append(folder.id)
        Task { await reload() }
    }

    func goBack() {
        guard pathStack.count > 1 else { return }
        // 返回上级即退出「全部照片」模式
        scanAllFolders = false
        allPhotos = []
        pathStack.removeLast()
        Task { await reload() }
    }

    // MARK: 派生数据
    var folders: [WebDAVItem] {
        items.filter { $0.isDirectory && $0.id != currentPath }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// 当前展示的图片集合：扫描模式下为全部照片，否则为当前文件夹图片
    private var images: [WebDAVItem] {
        if scanAllFolders { return allPhotos }
        return items.filter { !$0.isDirectory && $0.isImage }
    }

    func filteredImages(search: String) -> [WebDAVItem] {
        let sorted = applySort(images)
        if search.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func applySort(_ list: [WebDAVItem]) -> [WebDAVItem] {
        switch sortOption {
        case .nameAsc:  return list.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameDesc: return list.sorted { $0.name.localizedCompare($1.name) == .orderedDescending }
        case .dateAsc:  return list.sorted { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
        case .dateDesc: return list.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        case .shuffle:  return list.shuffled()
        }
    }

    private func normalizeServer(_ input: String) -> URL {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return URL(string: s) ?? URL(string: "https://example.com")!
    }
}
