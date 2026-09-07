import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var imageCache = ImageCache()
    @AppStorage("wd_columns") private var columns = 2
    @State private var cacheSize: Int64 = 0

    var body: some View {
        NavigationStack {
            List {
                Section("外观") {
                    Picker("主题", selection: $session.themeMode) {
                        ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                }
                Section("默认排序") {
                    Picker("排序", selection: $session.sortOption) {
                        ForEach(SortOption.allCases) { opt in
                            Label(opt.label, systemImage: opt.systemImage).tag(opt)
                        }
                    }
                }
                Section("浏览") {
                    Picker("显示列数", selection: $columns) {
                        Text("单列").tag(1)
                        Text("双列").tag(2)
                    }
                    Toggle("扫描所有子文件夹的照片", isOn: .init(
                        get: { session.scanAllFolders },
                        set: { _ in Task { await session.toggleScanAll() } }
                    ))
                }
                Section {
                    LabeledContent("本地缓存占用", value: ImageCache.formattedBytes(cacheSize))
                    Text("列表缩略图已压缩并保存到本机，下次打开 App 直接读取、无需重新从服务器下载。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        imageCache.clear()
                        cacheSize = 0
                    } label: {
                        Label("清除图片缓存", systemImage: "trash")
                    }
                } header: { Text("存储") }
                Section("账户") {
                    if let server = session.serverDisplay {
                        LabeledContent("服务器", value: server)
                    }
                    Button(role: .destructive) {
                        session.logout()
                        dismiss()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                Section("关于") {
                    LabeledContent("版本", value: "1.0.2")
                    LabeledContent("WebDAV 照片浏览器", value: "")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
            .task { cacheSize = imageCache.cachedBytes }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                cacheSize = imageCache.cachedBytes
            }
        }
    }
}
