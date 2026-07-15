import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var baseURL = ""
    @State private var adminKey = ""
    @State private var isChecking = false
    @State private var message: String?
    @State private var showKey = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Theme.primarySoft)
                                    .frame(width: 72, height: 72)

                                Image(systemName: "server.rack")
                                    .font(.system(size: 31, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Theme.primary)
                            }

                            Text("登录到 Sub2API")
                                .font(.system(size: 31, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.center)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            TextField(
                                "",
                                text: $baseURL,
                                prompt: Text("https://api.example.com").foregroundColor(Theme.subtleText)
                            )
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .formField(label: "服务器地址")

                            HStack(spacing: 10) {
                                Group {
                                    if showKey {
                                        TextField(
                                            "",
                                            text: $adminKey,
                                            prompt: Text("admin-xxxxxxxx").foregroundColor(Theme.subtleText)
                                        )
                                    } else {
                                        SecureField(
                                            "",
                                            text: $adminKey,
                                            prompt: Text("admin-xxxxxxxx").foregroundColor(Theme.subtleText)
                                        )
                                    }
                                }
                                .textInputAutocapitalization(.never)
                                .textContentType(.password)

                                Button(showKey ? "隐藏" : "显示") {
                                    showKey.toggle()
                                }
                                .font(.footnote.weight(.semibold))
                            }
                            .formField(label: "Admin Key")

                            if let message {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(isChecking ? Theme.primary : Theme.danger)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(isChecking ? Theme.primarySoft : Theme.dangerSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Button {
                                Task { await verifyAndEnter() }
                            } label: {
                                HStack(spacing: 10) {
                                    if isChecking {
                                        ProgressView()
                                    }
                                    Text(isChecking ? "连接中..." : "连接")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isChecking)
                        }
                        .padding(22)
                        .surfaceStyle(cornerRadius: 24)
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 34)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
            .background(Theme.page.ignoresSafeArea())
        }
    }

    private func verifyAndEnter() async {
        isChecking = true
        message = "正在验证服务器连接..."
        defer { isChecking = false }

        let client = APIClient(baseURL: baseURL, adminAPIKey: adminKey)
        do {
            async let settings = client.getAdminSettings()
            async let stats = client.getDashboardStats()
            _ = try await (settings, stats)
            session.saveServer(baseURL: baseURL, adminAPIKey: adminKey)
        } catch {
            if let userMessage = error.userFacingMessage { message = userMessage }
        }
    }
}

private extension View {
    func formField(label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.subtext)
            self
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.muted)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.border.opacity(0.45), lineWidth: 0.8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
