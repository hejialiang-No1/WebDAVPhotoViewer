import Foundation
import SwiftUI

// MARK: - 排序方式
enum SortOption: String, CaseIterable, Identifiable {
    case nameAsc
    case nameDesc
    case dateAsc
    case dateDesc
    case shuffle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nameAsc:  return "名称 ↑"
        case .nameDesc: return "名称 ↓"
        case .dateAsc:  return "时间 ↑"
        case .dateDesc: return "时间 ↓"
        case .shuffle:  return "乱序"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAsc, .nameDesc: return "textformat"
        case .dateAsc, .dateDesc: return "clock"
        case .shuffle:           return "shuffle"
        }
    }
}

// MARK: - 主题模式
enum ThemeMode: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
}

// MARK: - WebDAV 文件项
struct WebDAVItem: Identifiable, Equatable {
    let id: String            // 绝对 URL
    let name: String
    let isDirectory: Bool
    let contentType: String?
    let size: Int64
    let modified: Date?
    let estimatedHeight: CGFloat

    static let imageExtensions: Set<String> = [
        // 通用位图
        "jpg", "jpeg", "png", "gif", "bmp", "dib",
        "tif", "tiff", "webp", "heic", "heif",
        // 现代格式
        "jxl", "avif", "jp2", "jpx", "jpm",
        // 矢量 / 图标
        "svg", "ico", "cur",
        // 其它常见位图
        "tga", "pcx", "ppm", "pgm", "pbm",
        // 相机 RAW
        "raw", "dng", "cr2", "cr3", "nef", "arw",
        "raf", "orf", "rw2", "pef", "srw", "mrw", "3fr", "dcr", "kdc", "erf", "mos", "iiq"
    ]

    /// 格式展示名（大写，便于详情页/角标显示）
    static let formatNames: [String: String] = [
        "jpg": "JPEG", "jpeg": "JPEG", "png": "PNG", "gif": "GIF", "bmp": "BMP", "dib": "BMP",
        "tif": "TIFF", "tiff": "TIFF", "webp": "WebP", "heic": "HEIC", "heif": "HEIF",
        "jxl": "JXL", "avif": "AVIF", "jp2": "JP2", "jpx": "JP2", "jpm": "JP2",
        "svg": "SVG", "ico": "ICO", "cur": "CUR", "tga": "TGA", "pcx": "PCX",
        "ppm": "PPM", "pgm": "PGM", "pbm": "PBM",
        "raw": "RAW", "dng": "DNG", "cr2": "CR2", "cr3": "CR3", "nef": "NEF", "arw": "ARW",
        "raf": "RAF", "orf": "ORF", "rw2": "RW2", "pef": "PEF", "srw": "SRW", "mrw": "MRW",
        "3fr": "3FR", "dcr": "DCR", "kdc": "KDC", "erf": "ERF", "mos": "MOS", "iiq": "IIQ"
    ]

    // 系统（UIImage / ImageIO）能直接解码渲染的格式。
    // 这些会被瀑布流/详情页真正「加载」出像素；其余格式仅做「识别」（列出 + 角标），
    // 因 iOS 原生不支持其像素解码（如相机 RAW），详情页会提示无法预览。
    static let decodableExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff", "webp", "heic", "heif",
        "jp2", "jpx", "jxl", "avif", "svg", "ico", "tga", "ppm", "pgm", "pbm"
    ]

    var isImage: Bool {
        if let ct = contentType, ct.hasPrefix("image/") { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return WebDAVItem.imageExtensions.contains(ext)
    }

    /// 该图片能否被系统直接解码（用于判断是加载像素还是仅识别）
    var isDecodable: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        if Self.decodableExtensions.contains(ext) { return true }
        if let ct = contentType, ct.hasPrefix("image/") { return true }
        return false
    }

    /// 识别出的照片格式（如 JPEG / HEIC / RAW / WebP…）
    var formatLabel: String {
        let ext = (name as NSString).pathExtension.lowercased()
        if let known = WebDAVItem.formatNames[ext] { return known }
        if let ct = contentType, ct.hasPrefix("image/") {
            return String(ct.split(separator: "/").last ?? "image").uppercased()
        }
        return ext.uppercased().isEmpty ? "图片" : ext.uppercased()
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - 通用扩展
extension String {
    var nilIfEmpty: String? { self.isEmpty ? nil : self }
}

extension View {
    /// 液态玻璃卡片外观
    func glassCard(cornerRadius: CGFloat = 16, opacity: Double = 0.5) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(opacity), lineWidth: 1)
            )
    }
}
