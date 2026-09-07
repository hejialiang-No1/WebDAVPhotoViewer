import Foundation
import Combine

/// 缓存每个文件夹的「封面图片」（即该文件夹内的第一张图片）：
/// 避免瀑布流中每个文件夹格重复发起 PROPFIND，列表结果按 folder.id 缓存。
@MainActor final class FolderCoverStore: ObservableObject {
    @Published private(set) var coverItems: [String: WebDAVItem] = [:]
    private var tasks: [String: Task<WebDAVItem?, Never>] = [:]

    /// 返回该文件夹内用于做封面的第一张图片（按名称升序取第一张）。
    /// 若未在缓存中则发起一次列目录请求，并对并发请求做去重。
    func firstImage(for folder: WebDAVItem, client: WebDAVClient) async -> WebDAVItem? {
        if let cached = coverItems[folder.id] { return cached }
        if let t = tasks[folder.id] { return await t.value }
        let task = Task { [self] in
            defer { tasks[folder.id] = nil }
            do {
                let contents = try await client.listFiles(at: folder.id)
                let first = contents
                    .filter { !$0.isDirectory && $0.isImage }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                    .first
                await MainActor.run { coverItems[folder.id] = first }
                return first
            } catch {
                await MainActor.run { coverItems[folder.id] = nil }
                return nil
            }
        }
        tasks[folder.id] = task
        return await task.value
    }

    func clear() {
        coverItems.removeAll()
        tasks.removeAll()
    }
}
