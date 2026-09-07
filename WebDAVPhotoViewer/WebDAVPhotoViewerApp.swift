import SwiftUI

@main
struct WebDAVPhotoViewerApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(session.themeMode.colorScheme)
        }
    }
}
