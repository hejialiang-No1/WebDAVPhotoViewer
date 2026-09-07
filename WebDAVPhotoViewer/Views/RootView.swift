import SwiftUI

/// 根视图：根据登录状态切换登录页 / 图库页
struct RootView: View {
    @EnvironmentObject var session: SessionStore

    var body: some View {
        Group {
            if session.isLoggedIn {
                GalleryView()
            } else {
                LoginView()
            }
        }
    }
}
