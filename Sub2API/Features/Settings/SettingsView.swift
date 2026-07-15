import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showingAddServer = false
    @State private var showingLogoutConfirmation = false
    @State private var isExitingServer = false

    var body: some View {
        ScreenScroll(topPadding: AppLayout.floatingNavContentTopPadding) {
            SectionCard("当前服务器") {
                if session.profiles.isEmpty {
                    Text("还没有服务器。")
                        .foregroundStyle(Theme.subtext)
                } else {
                    VStack(spacing: 12) {
                        ForEach(session.profiles) { profile in
                            ServerProfileRow(
                                profile: profile,
                                isActive: profile.id == session.activeProfileID,
                                onSelect: { session.switchProfile(profile) },
                                onDelete: { session.removeProfile(profile) }
                            )
                            .padding(12)
                            .background(Theme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }

            SectionCard("操作") {
                VStack(spacing: 10) {
                    Button {
                        showingAddServer = true
                    } label: {
                        Label("添加服务器", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        Label(isExitingServer ? "正在切换服务器..." : "退出当前服务器", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExitingServer || session.activeProfileID.isEmpty)
                }
            }
        }
        .overlay(alignment: .top) {
            FloatingNavigationBar(title: "服务器") {
                EmptyView()
            } trailing: {
                EmptyView()
            }
        }
        .hideSystemNavigationChrome()
        .alert("退出当前服务器", isPresented: $showingLogoutConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) {
                Task { await exitCurrentServer() }
            }
        } message: {
            Text("会删除当前服务器配置，并自动尝试连接剩余服务器。15 秒内无响应的服务器会被移除。")
        }
        .sheet(isPresented: $showingAddServer) {
            NavigationStack {
                AddServerView {
                    showingAddServer = false
                }
            }
        }
    }

    private func exitCurrentServer() async {
        guard !isExitingServer else { return }
        isExitingServer = true
        defer { isExitingServer = false }

        await session.exitCurrentServerAndActivateFallback(timeoutSeconds: 15)
    }
}

private struct ServerProfileRow: View {
    let profile: ServerProfile
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.label)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text(profile.baseURL)
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                        .lineLimit(2)
                    Text("更新时间 \(profile.updatedAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleText)
                }
                Spacer()
                if isActive {
                    StatusPill(text: "当前使用", tone: .success)
                }
            }

            HStack {
                Button(isActive ? "已选中" : "切换到此服务器", action: onSelect)
                    .buttonStyle(.borderedProminent)
                    .disabled(isActive)
                Button("删除", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

private struct AddServerView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = ""
    @State private var adminKey = ""
    @State private var showKey = false
    @State private var isChecking = false
    @State private var message: String?
    let onSaved: () -> Void

    var body: some View {
        Form {
            Section("连接信息") {
                TextField("https://api.example.com", text: $baseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)

                HStack {
                    if showKey {
                        TextField("admin-xxxxxxxx", text: $adminKey)
                    } else {
                        SecureField("admin-xxxxxxxx", text: $adminKey)
                    }
                    Button(showKey ? "隐藏" : "显示") {
                        showKey.toggle()
                    }
                }
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(isChecking ? Theme.primary : Theme.danger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: AppLayout.floatingNavFormTopInset)
        }
        .overlay(alignment: .top) {
            FloatingNavigationBar(title: "添加服务器") {
                GlassNavButton(systemImage: "xmark") {
                    dismiss()
                }
            } trailing: {
                GlassNavButton(
                    systemImage: isChecking ? "hourglass" : "checkmark",
                    isDisabled: isChecking || baseURL.isEmpty || adminKey.isEmpty
                ) {
                    Task { await verifyAndSave() }
                }
            }
        }
        .hideSystemNavigationChrome()
    }

    private func verifyAndSave() async {
        isChecking = true
        message = "正在检测当前服务是否可用..."
        defer { isChecking = false }

        do {
            let client = APIClient(baseURL: baseURL, adminAPIKey: adminKey)
            async let settings = client.getAdminSettings()
            async let stats = client.getDashboardStats()
            _ = try await (settings, stats)
            session.saveServer(baseURL: baseURL, adminAPIKey: adminKey)
            onSaved()
        } catch {
            if let userMessage = error.userFacingMessage { message = userMessage }
        }
    }
}
