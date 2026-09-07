import SwiftUI
import Combine

/// 记录每张图片的宽高比，供瀑布流计算高度
@MainActor final class ImageSizeStore: ObservableObject {
    @Published private(set) var aspects: [String: CGFloat] = [:]

    func set(_ id: String, _ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        aspects[id] = size.height / size.width
    }
}

/// 异步加载远程图片（带磁盘缓存），加载完成后回调尺寸
@MainActor final class RemoteImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = true
    @Published var didFail = false

    private var task: Task<Void, Never>?

    init(item: WebDAVItem, client: WebDAVClient, cache: ImageCache,
         variant: ImageVariant = .original, onSize: @escaping (CGSize) -> Void) {
        task = Task {
            do {
                let data = try await cache.data(for: item, client: client, variant: variant)
                guard let img = ImageCache.decodeImage(from: data) else { throw WebDAVError.invalidImage }
                if Task.isCancelled { return }
                self.image = img
                self.isLoading = false
                onSize(img.size)
            } catch is CancellationError {
                // 已取消
            } catch {
                if !Task.isCancelled {
                    self.didFail = true
                    self.isLoading = false
                }
            }
        }
    }

    deinit { task?.cancel() }
}

/// 瀑布流单格：玻璃卡片 + 远程图片 + 格式角标
struct PhotoCell: View {
    let item: WebDAVItem
    let client: WebDAVClient
    let cache: ImageCache
    @ObservedObject var sizeStore: ImageSizeStore
    @StateObject private var loader: RemoteImageLoader
    @State private var saving = false
    @State private var savedTick = false

    init(item: WebDAVItem, client: WebDAVClient, cache: ImageCache, sizeStore: ImageSizeStore) {
        self.item = item
        self.client = client
        self.cache = cache
        self._sizeStore = ObservedObject(wrappedValue: sizeStore)
        // 列表用压缩缩略图，省流量；点开详情页才加载原图
        _loader = StateObject(wrappedValue: RemoteImageLoader(item: item, client: client,
                                                               cache: cache, variant: .thumbnail) { size in
            sizeStore.set(item.id, size)
        })
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if loader.didFail {
                // 已识别但系统无法解码像素（如相机 RAW）：仍展示条目 + 格式角标，便于「识别」
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 26))
                    Text("无法预览")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
            } else {
                Color(uiColor: .secondarySystemBackground)
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        .overlay(alignment: .bottomLeading) {
            Text(item.formatLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                .padding(6)
        }
        .overlay(alignment: .center) {
            if saving {
                ProgressView().tint(.white)
                    .padding(14)
                    .background(.ultraThinMaterial, in: Capsule())
            } else if savedTick {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .onLongPressGesture {
            Task { await saveOriginal() }
        }
    }

    /// 长按：下载原图（全分辨率）并保存到系统相册
    private func saveOriginal() async {
        guard !saving else { return }
        saving = true
        do {
            let data = try await cache.data(for: item, client: client, variant: .original)
            if let img = ImageCache.decodeImage(from: data) {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            }
            withAnimation { savedTick = true }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation { savedTick = false }
        } catch {
            // 失败不提示，长按仅作为快捷保存
        }
        saving = false
    }
}

/// 详情页可缩放图片
struct ZoomableImageView: View {
    let item: WebDAVItem
    let client: WebDAVClient
    let cache: ImageCache
    @StateObject private var loader: RemoteImageLoader
    @State private var scale: CGFloat = 1
    @State private var offset = CGSize.zero

    /// 最大放大倍数（双击 / 捏合均可到该上限，满足「放大到最高」）
    private let maxScale: CGFloat = 8

    init(item: WebDAVItem, client: WebDAVClient, cache: ImageCache) {
        self.item = item
        self.client = client
        self.cache = cache
        // 全屏查看加载原图（全分辨率）
        _loader = StateObject(wrappedValue: RemoteImageLoader(item: item, client: client,
                                                               cache: cache, variant: .original) { _ in })
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnifyGesture)
                    .gesture(dragGesture)
                    .onTapGesture(count: 2) {
                        withAnimation {
                            scale = scale > 1 ? 1 : maxScale
                            if scale == 1 { offset = .zero }
                        }
                    }
            } else if loader.didFail {
                VStack(spacing: 12) {
                    Image(systemName: "photo").font(.largeTitle)
                    Text("无法预览该格式（\(item.formatLabel)）")
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, min(value, maxScale))
            }
            .onEnded { _ in
                if scale < 1 { withAnimation { scale = 1; offset = .zero } }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 { offset = value.translation }
            }
            .onEnded { _ in }
    }
}
