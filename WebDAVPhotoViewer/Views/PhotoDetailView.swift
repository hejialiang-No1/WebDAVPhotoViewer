import SwiftUI

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct PhotoDetailView: View {
    let item: WebDAVItem
    let client: WebDAVClient
    let cache: ImageCache
    let allItems: [WebDAVItem]

    @State private var index: Int
    @State private var showInfo = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var toast: String?
    @Environment(\.dismiss) private var dismiss

    init(item: WebDAVItem, client: WebDAVClient, cache: ImageCache, allItems: [WebDAVItem]) {
        self.item = item
        self.client = client
        self.cache = cache
        self.allItems = allItems
        _index = State(initialValue: max(0, allItems.firstIndex(where: { $0.id == item.id }) ?? 0))
    }

    private var currentItem: WebDAVItem? { allItems[safe: index] }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $index) {
                ForEach(Array(allItems.enumerated()), id: \.element.id) { i, it in
                    ZoomableImageView(item: it, client: client, cache: cache)
                        .tag(i)
                        .onLongPressGesture {
                            Task { await prepareShare(for: it) }
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .background(Color.black)
            .ignoresSafeArea()

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                }
                Spacer()
                if let current = currentItem {
                    Text(current.name)
                        .lineLimit(1)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                Spacer()
                Button { Task { await prepareShare(for: currentItem ?? item) } } label: {
                    Image(systemName: "square.and.arrow.up").font(.title2)
                }
                Button { showInfo.toggle() } label: {
                    Image(systemName: "info.circle").font(.title2)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 0, opacity: 0.25)

            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 64)
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .sheet(isPresented: $showInfo) {
            if let current = currentItem { infoPanel(current) }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
    }

    /// 准备分享/保存：拉取原图（全分辨率）后弹出系统分享面板（含「保存图像」「存储到文件」）
    private func prepareShare(for target: WebDAVItem) async {
        do {
            let data = try await cache.data(for: target, client: client, variant: .original)
            if let img = UIImage(data: data) {
                await MainActor.run { shareItems = [img]; showShare = true }
            } else {
                // 无法解码为图片（如某些 RAW）：以原始文件形式分享
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(target.name)
                try? data.write(to: tmp)
                await MainActor.run { shareItems = [tmp]; showShare = true }
            }
        } catch {
            await MainActor.run { showToast("下载失败，请重试") }
        }
    }

    private func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { toast = nil }
        }
    }

    private func infoPanel(_ item: WebDAVItem) -> some View {
        NavigationStack {
            List {
                LabeledContent("名称", value: item.name)
                if let d = item.modified { LabeledContent("修改时间", value: d.formatted()) }
                LabeledContent("大小", value: item.formattedSize)
                LabeledContent("格式", value: item.formatLabel)
                LabeledContent("类型", value: item.contentType ?? "未知")
            }
            .navigationTitle("图片信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { showInfo = false } }
        }
    }
}

/// 系统分享 / 保存面板（含「存储图像」「存储到文件」）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excluded: [UIActivity.ActivityType] = []

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = excluded
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
