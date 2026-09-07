import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionStore
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focused: Field?
    /// 登录后弹出目录选择
    @State private var showDirPicker = false
    @State private var connectError = false

    enum Field { case server, username, password }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                ScrollView {
                    VStack(spacing: 22) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 56))
                                .foregroundStyle(.white)
                                .padding(20)
                                .background(.ultraThinMaterial, in: Circle())
                            Text("WebDAV 照片").font(.title.bold())
                            Text("登录你的远程相册").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.top, 30)

                        VStack(spacing: 16) {
                            field("服务器地址", systemImage: "server.rack", text: $server,
                                  placeholder: "https://nas.example.com/dav", field: .server)
                            Divider()
                            field("用户名", systemImage: "person", text: $username,
                                  placeholder: "admin", field: .username)
                            Divider()
                            secureField
                        }
                        .padding(18)
                        .glassCard(cornerRadius: 22)

                        Button(action: submit) {
                            HStack {
                                if session.isLoading { ProgressView().tint(.white) }
                                Text(session.isLoading ? "连接中…" : "登录并选择目录")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(session.isLoading || server.isEmpty)
                        .padding(.horizontal, 4)

                        if let error = session.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showDirPicker) {
            DirectoryBrowserView()
                .environmentObject(session)
        }
    }

    private var secureField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("密码").font(.caption).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "lock").foregroundStyle(.secondary)
                SecureField("密码", text: $password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
            }
        }
    }

    private func field(_ title: String, systemImage: String, text: Binding<String>,
                       placeholder: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                Image(systemName: systemImage).foregroundStyle(.secondary)
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(field == .server ? .URL : .default)
                    .focused($focused, equals: field)
                    .submitLabel(field == .username ? .next : .go)
            }
        }
    }

    private func submit() {
        focused = nil
        guard !server.isEmpty else { return }
        Task {
            let ok = await session.connect(server: server, username: username, password: password)
            if ok {
                await MainActor.run { showDirPicker = true }
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.29, green: 0.42, blue: 0.97),
                     Color(red: 0.61, green: 0.36, blue: 0.89)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}
