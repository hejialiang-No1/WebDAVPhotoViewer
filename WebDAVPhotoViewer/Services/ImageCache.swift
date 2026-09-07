import Foundation
import UIKit
import ImageIO

/// 图片加载变体：缩略图（压缩、省流量）/ 原图（全分辨率）
enum ImageVariant {
    case thumbnail
    case original
}

/// 磁盘图片缓存：按 item.id 哈希落盘，缩略图与原图分目录存储
/// - 缩略图：下载原图后等比缩放到 ThumbnailMaxPixels 以内，转 JPEG 压缩，体积大幅减小
/// - 原图：保留服务器返回的原始字节，供全屏查看
final class ImageCache: ObservableObject {
    /// 缩略图最长边像素：列表双列约 184pt 宽，@3x ≈ 552 设备像素，600 足够清晰且体积小
    static let thumbnailMaxPixels: CGFloat = 600
    /// 缩略图 JPEG 压缩质量（越小越快、体积越小）
    static let thumbnailQuality: CGFloat = 0.72

    /// 解码图片数据：优先 UIImage，失败再用 ImageIO 兜底。
    /// ImageIO 可解码 UIImage 不直接支持、但系统能读的格式（如 JPEG2000 / 部分专有封装），
    /// 从而让「自动扫描」尽可能多地识别并加载各类图片。
    static func decodeImage(from data: Data) -> UIImage? {
        if let img = UIImage(data: data) { return img }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opt = [kCGImageSourceShouldCache: true] as CFDictionary
        guard let cg = CGImageSourceCreateImageAtIndex(src, 0, opt) else { return nil }
        return UIImage(cgImage: cg)
    }

    let originalDir: URL
    let thumbDir: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        originalDir = base.appendingPathComponent("webdav_images", isDirectory: true)
        thumbDir = base.appendingPathComponent("webdav_thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: originalDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
    }

    private func originalURL(for item: WebDAVItem) -> URL {
        let hashed = item.id.sha256
        var ext = (item.name as NSString).pathExtension.lowercased()
        if ext.isEmpty { ext = "img" }
        return originalDir.appendingPathComponent("\(hashed).\(ext)")
    }

    private func thumbURL(for item: WebDAVItem) -> URL {
        originalURL(for: item).deletingLastPathComponent()
            .appendingPathComponent("\(item.id.sha256).thumb.jpg")
    }

    /// 读取指定变体：命中缓存直接返回，未命中则下载并按需生成缩略图
    func data(for item: WebDAVItem, client: WebDAVClient, variant: ImageVariant) async throws -> Data {
        switch variant {
        case .original:
            let url = originalURL(for: item)
            if FileManager.default.fileExists(atPath: url.path) {
                return try Data(contentsOf: url)
            }
            let data = try await client.downloadData(at: item.id)
            try? data.write(to: url)
            return data

        case .thumbnail:
            let turl = thumbURL(for: item)
            if FileManager.default.fileExists(atPath: turl.path) {
                return try Data(contentsOf: turl)
            }
            // 缩略图依赖原图：确保原图已缓存，再缩放压缩
            let original = try await data(for: item, client: client, variant: .original)
            if let thumb = Self.makeThumbnail(from: original,
                                               maxPixels: Self.thumbnailMaxPixels,
                                               quality: Self.thumbnailQuality) {
                try? thumb.write(to: turl)
                return thumb
            }
            return original
        }
    }

    /// 把原图等比缩放到 maxPixels 以内并转 JPEG，显著压缩体积。
    /// 关键点：使用 ImageIO 在**解码阶段直接降采样**（kCGImageSourceThumbnailMaxPixelSize），
    /// 绝不把整张原图解码成全分辨率位图，因此大图（如 6000×4000）也能毫秒级出缩略图、几乎不占内存。
    static func makeThumbnail(from data: Data, maxPixels: CGFloat, quality: CGFloat) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        let img = UIImage(cgImage: cg)
        return img.jpegData(compressionQuality: quality)
    }

    func clear() {
        try? FileManager.default.removeItem(at: originalDir)
        try? FileManager.default.removeItem(at: thumbDir)
        try? FileManager.default.createDirectory(at: originalDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
    }

    // MARK: 缓存占用统计
    /// 已落盘的总字节数（原图 + 缩略图）。缩略图为压缩后的 JPEG，列表直接读它，
    /// 下次打开 App 无需重新从服务器下载，省流量、秒开。
    var cachedBytes: Int64 {
        Self.directorySize(originalDir) + Self.directorySize(thumbDir)
    }

    /// 缩略图目录字节数（列表用的压缩图）
    var thumbnailBytes: Int64 { Self.directorySize(thumbDir) }

    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url,
              includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = vals.fileSize { total += Int64(size) }
        }
        return total
    }

    static func formattedBytes(_ bytes: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useKB, .useMB, .useGB]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }
}
