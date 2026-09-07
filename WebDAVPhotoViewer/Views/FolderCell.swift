import SwiftUI
import Combine

/// 文件夹格加载器：取出文件夹内第一张图片，下载其压缩缩略图作为封面
@MainActor final class FolderCoverLoader: ObservableObject {
    @Published var coverImage: UIImage?
    @Published var isLoading = true
    @Published var hasImage = false

    private var task: Task<Void, Never>?

    init(folder: WebDAVItem, client: WebDAVClient, cache: ImageCache,
         sizeStore: ImageSizeStore, coverStore: FolderCoverStore) {
        task = Task {
            let coverItem = await coverStore.firstImage(for: folder, client: client)
            guard let coverItem else {
                await MainActor.run { self.isLoading = false; self.hasImage = false }
                return
            }
            do {
                let data = try await cache.data(for: coverItem, client: client, variant: .thumbnail)
                guard let img = ImageCache.decodeImage(from: data) else {
                    await MainActor.run { self.isLoading = false; self.hasImage = false }
                    return
                }
                if Task.isCancelled { return }
                await MainActor.run {
                    self.coverImage = img
                    self.hasImage = true
                    self.isLoading = false
                    sizeStore.set(folder.id, img.size)
                }
            } catch is CancellationError {
                // 已取消
            } catch {
                await MainActor.run { self.isLoading = false; self.hasImage = false }
            }
        }
    }

    deinit { task?.cancel() }
}

/// 瀑布流中的文件夹格：以文件夹内第一张图片作封面，点击进入
struct FolderCell: View {
    let item: WebDAVItem
    let client: WebDAVClient
    let cache: ImageCache
    @ObservedObject var sizeStore: ImageSizeStore
    @ObservedObject var coverStore: FolderCoverStore
    var onOpen: () -> Void

    @StateObject private var loader: FolderCoverLoader

    init(item: WebDAVItem, client: WebDAVClient, cache: ImageCache,
         sizeStore: ImageSizeStore, coverStore: FolderCoverStore, onOpen: @escaping () -> Void) {
        self.item = item
        self.client = client
        self.cache = cache
        self._sizeStore = ObservedObject(wrappedValue: sizeStore)
        self._coverStore = ObservedObject(wrappedValue: coverStore)
        self.onOpen = onOpen
        _loader = StateObject(wrappedValue: FolderCoverLoader(folder: item, client: client,
                                                              cache: cache, sizeStore: sizeStore, coverStore: coverStore))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = loader.coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if loader.isLoading {
                Color(uiColor: .secondarySystemBackground)
                    .overlay(ProgressView())
            } else {
                // 该文件夹内没有可识别的图片：显示文件夹占位
                Color(uiColor: .secondarySystemBackground)
                    .overlay(Image(systemName: "folder.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary))
            }

            // 底部信息条：文件夹名
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13, weight: .medium))
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}
