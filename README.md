# WebDAVPhotoViewer

iOS WebDAV 远程图片查看器（SwiftUI，Apple 审美 + 液态玻璃风格）。

## 功能
- **两列瀑布流**：自定义 MasonryLayout，最短列优先排布，自适应列宽。
- **液态玻璃**：导航栏 / 卡片 / 菜单 / 详情栏统一使用 `.ultraThinMaterial` + 圆角描边。
- **WebDAV 登录**：服务器 + 账号 + 密码，凭据存 Keychain；支持 Basic / Digest 认证、自签名证书放行（Nextcloud / ownCloud / 群晖等通用）。
- **登录时选择起始目录**：登录后浏览服务器目录，选定起始目录，之后每次打开直接从该目录起步。
- **排序**：名称↑↓、时间↑↓、乱序，工具栏一键切换。
- **深浅色切换**：系统 / 浅色 / 深色，实时生效。
- **递归扫描所有照片**：从当前目录递归遍历子文件夹，收集全部图片（默认限深 8 层、上限 3000 张）。
- **识别所有图片格式**：JPEG / PNG / GIF / BMP / TIFF / WebP / HEIC / HEIF / JXL / AVIF / SVG / ICO / JP2 及相机 RAW（CR2 / CR3 / NEF / ARW / DNG / RAF / ORF / RW2 / PEF / SRW / MRW 等）。iOS 原生解不出的 RAW 仅识别不下像素。
- **缩略图压缩 + 原图全屏**：列表用 ImageIO 解码阶段降采样生成的压缩缩略图（最长边 600px，JPEG 0.72），省流量；点开全屏才加载原图，支持放大到 8×。
- **缩略图本地持久化**：压缩缩略图落盘缓存，下次打开秒读，设置页可查看占用并清除。
- **单 / 双列切换**：工具栏或设置页切换，用 `@AppStorage` 持久化。
- **长按下载 / 分享**：列表长按存原图到相册；详情页长按或点分享按钮弹出系统分享面板。
- 附加工夫：文件夹下钻、名称搜索、图片详情页（EXIF / 格式信息）、退出登录。

## 版本
当前 **1.0.4**。

## 编译 / 出 IPA
1. 在装有完整 Xcode 的 Mac 上双击 `WebDAVPhotoViewer.xcodeproj`。
2. 把 `PRODUCT_BUNDLE_IDENTIFIER`（占位 `com.yourcompany.WebDAVPhotoViewer`）改为你的 App ID。
3. Signing & Capabilities → Team 选企业开发者账号，Provisioning Profile 选 **In-House（企业分发）** 描述文件。
4. `Product ▸ Archive` → Organizer 里 `Distribute App ▸ Enterprise` 导出 `.ipa`。
   或直接跑脚本（需企业证书 + 描述文件）：
   ```bash
   ./build_ipa.sh -t <TeamID> -i "iPhone Distribution: 公司 (TEAMID)" -p <描述文件UUID> -b com.yourcompany.WebDAVPhotoViewer
   ```
   已有未签名包时也可重签：
   ```bash
   ./resign.sh -i "iPhone Distribution: 公司 (TEAMID)" -p InHouse.mobileprovision -b com.yourcompany.WebDAVPhotoViewer WebDAVPhotoViewer-1.0.4-unsigned.ipa
   ```
最低支持 **iOS 16**。

## 目录结构
```
WebDAVPhotoViewer/
├── WebDAVPhotoViewer.xcodeproj
└── WebDAVPhotoViewer/
    ├── WebDAVPhotoViewerApp.swift
    ├── SessionStore.swift          登录 / 目录 / 排序 / 主题 / 扫描状态
    ├── Models.swift                SortOption / ThemeMode / WebDAVItem + 格式识别
    ├── Services/                   WebDAVClient / ImageCache / KeychainHelper
    └── Views/                      Login / DirectoryBrowser / Gallery / PhotoDetail / Settings / MasonryLayout / RemoteImageView / RootView
```
