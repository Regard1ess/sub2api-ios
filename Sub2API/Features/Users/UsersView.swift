import SwiftUI
import UIKit

@MainActor
final class UsersViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var users: [AdminUser] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(client: APIClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await client.listUsers(search: searchText)
            users = page.items.sorted {
                ($0.lastUsedAt ?? $0.updatedAt ?? $0.createdAt ?? "") > ($1.lastUsedAt ?? $1.updatedAt ?? $1.createdAt ?? "")
            }
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }
}

struct UsersView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel = UsersViewModel()
    @State private var showingCreateUser = false

    var body: some View {
        ScreenScroll(topPadding: AppLayout.floatingNavContentTopPadding) {
            SearchField(placeholder: "搜索邮箱、用户名或备注", text: $viewModel.searchText) {
                Task { await viewModel.load(client: session.apiClient) }
            }

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            if viewModel.isLoading && viewModel.users.isEmpty {
                LoadingOverlay(message: "正在加载用户...")
            } else if viewModel.users.isEmpty {
                EmptyState(title: "暂无用户", message: "当前搜索条件下没有匹配用户。")
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.users) { user in
                        NavigationLink(value: user) {
                            UserRow(user: user)
                                .padding(14)
                                .surfaceStyle(cornerRadius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            FloatingNavigationBar(title: "用户") {
                EmptyView()
            } trailing: {
                GlassNavButton(systemImage: "plus") {
                    showingCreateUser = true
                }
            }
        }
        .hideSystemNavigationChrome()
        .navigationDestination(for: AdminUser.self) { user in
            UserDetailView(userID: user.id)
        }
        .sheet(isPresented: $showingCreateUser) {
            NavigationStack {
                CreateUserView {
                    showingCreateUser = false
                    Task { await viewModel.load(client: session.apiClient) }
                }
            }
        }
        .refreshable {
            await viewModel.load(client: session.apiClient)
        }
        .task(id: session.activeProfileID) {
            await viewModel.load(client: session.apiClient)
        }
    }
}

private struct UserRow: View {
    let user: AdminUser

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.email)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(user.username ?? user.notes ?? "未命名") · 最近 \(AppFormatters.dateTime(user.lastUsedAt ?? user.updatedAt ?? user.createdAt))")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                        .lineLimit(1)
                }
                Spacer()
                StatusPill(text: user.status ?? "active", tone: user.status == "disabled" ? .neutral : .success)
            }

            HStack(spacing: 8) {
                smallMetric("余额", AppFormatters.money(user.balance))
                smallMetric("并发", AppFormatters.compactNumber(user.currentConcurrency ?? user.concurrency))
                smallMetric("角色", user.role ?? "user")
            }
        }
        .padding(.vertical, 6)
    }

    private func smallMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.subtext)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Theme.muted)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct CreateUserView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var notes = ""
    @State private var role = "user"
    @State private var status = "active"
    @State private var balance = ""
    @State private var concurrency = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    let onSaved: () -> Void

    var body: some View {
        Form {
            Section("基础信息") {
                TextField("邮箱", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                SecureField("密码", text: $password)
                TextField("用户名（可选）", text: $username)
                TextField("备注（可选）", text: $notes)
            }

            Section("权限与状态") {
                Picker("角色", selection: $role) {
                    Text("user").tag("user")
                    Text("admin").tag("admin")
                }
                Picker("状态", selection: $status) {
                    Text("active").tag("active")
                    Text("disabled").tag("disabled")
                }
            }

            Section("高级参数") {
                TextField("余额", text: $balance)
                    .keyboardType(.decimalPad)
                TextField("并发", text: $concurrency)
                    .keyboardType(.numberPad)
            }

            if let errorMessage {
                Section {
                    ErrorBanner(message: errorMessage)
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: AppLayout.floatingNavFormTopInset)
        }
        .overlay(alignment: .top) {
            FloatingNavigationBar(title: "添加用户") {
                GlassNavButton(systemImage: "xmark") {
                    dismiss()
                }
            } trailing: {
                GlassNavButton(
                    systemImage: isSaving ? "hourglass" : "checkmark",
                    isDisabled: isSaving || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
                ) {
                    Task { await save() }
                }
            }
        }
        .hideSystemNavigationChrome()
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let payload = CreateUserPayload(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                username: username.nilIfBlank,
                notes: notes.nilIfBlank,
                role: role,
                status: status,
                balance: Double(balance),
                concurrency: Int(concurrency)
            )
            _ = try await session.apiClient.createUser(payload)
            onSaved()
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }
}

struct UserDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let userID: Int
    @State private var user: AdminUser?
    @State private var keys: [AdminAPIKey] = []
    @State private var usage: UsageStats?
    @State private var trend: [TrendPoint] = []
    @State private var range: RangeKey = .week
    @State private var amount = "10"
    @State private var operation = "add"
    @State private var notes = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                if isLoading && user == nil {
                    LoadingOverlay(message: "正在加载用户详情...")
                }

                if let user {
                    SectionCard("基础信息") {
                        VStack(spacing: 10) {
                            detailRow("邮箱", user.email)
                            detailRow("用户名", user.username ?? "--")
                            detailRow("余额", AppFormatters.money(user.balance))
                            detailRow("最后使用", AppFormatters.dateTime(user.lastUsedAt ?? user.updatedAt ?? user.createdAt))

                            Button(user.status == "disabled" ? "启用用户" : "禁用用户") {
                                Task { await toggleStatus() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(user.status == "disabled" ? Theme.primary : Theme.danger)
                            .disabled(user.role?.lowercased() == "admin")
                        }
                    }

                    SectionCard("总用量") {
                        Picker("时间范围", selection: $range) {
                            ForEach(RangeKey.allCases) { item in
                                Text(item.label).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            MetricCard("请求", value: AppFormatters.compactNumber(usage?.totalRequests))
                            MetricCard("Token", value: AppFormatters.compactNumber(usage?.totalTokens))
                            MetricCard("成本", value: AppFormatters.money(usage?.totalAccountCost ?? usage?.totalActualCost ?? usage?.totalCost))
                        }

                        if trend.count > 1 {
                            SimpleLineChart(points: trend, value: { Double($0.totalTokens) }, color: Theme.primary)
                        } else {
                            ChartPlaceholder(message: "暂无趋势数据")
                        }
                    }

                    SectionCard("API Keys") {
                        if keys.isEmpty {
                            Text("暂无 Key")
                                .font(.footnote)
                                .foregroundStyle(Theme.subtext)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(keys) { item in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(item.name.isEmpty ? "Key #\(item.id)" : item.name)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            Spacer()
                                            Button("复制") {
                                                UIPasteboard.general.string = item.key
                                            }
                                            .font(.caption.weight(.semibold))
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            StatusPill(text: item.status, tone: item.status == "active" ? .success : .neutral)
                                        }
                                        Text(item.key)
                                            .font(.caption)
                                            .foregroundStyle(Theme.subtext)
                                            .lineLimit(2)
                                            .textSelection(.enabled)
                                        Text("已用 \(AppFormatters.compactNumber(item.quotaUsed)) · 最后 \(AppFormatters.dateTime(item.lastUsedAt ?? item.updatedAt ?? item.createdAt))")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.subtext)
                                    }
                                    .padding(12)
                                    .background(Theme.muted)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }

                    SectionCard("余额操作") {
                        Picker("操作", selection: $operation) {
                            Text("充值").tag("add")
                            Text("扣减").tag("subtract")
                            Text("设为").tag("set")
                        }
                        .pickerStyle(.segmented)

                        TextField("金额", text: $amount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)

                        TextField("备注（可选）", text: $notes)
                            .textFieldStyle(.roundedBorder)

                        Button("确认提交") {
                            Task { await submitBalance() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, AppLayout.floatingNavContentTopPadding)
            .padding(.bottom, 132)
        }
        .background(Theme.page)
        .overlay(alignment: .top) {
            FloatingNavigationBar(title: user?.email ?? "用户详情") {
                GlassNavButton(systemImage: "chevron.left") {
                    dismiss()
                }
            } trailing: {
                EmptyView()
            }
        }
        .hideSystemNavigationChrome()
        .refreshable {
            await load()
        }
        .task(id: userID) {
            await load()
        }
        .onChange(of: range) { _ in
            Task { await loadUsage() }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(Theme.subtext)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.subheadline)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let user = session.apiClient.getUser(userID)
            async let keys = session.apiClient.listUserAPIKeys(userId: userID)
            self.user = try await user
            let keyPage = try await keys
            self.keys = keyPage.items
            await loadUsage()
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }

    private func loadUsage() async {
        do {
            let dateRange = range.dateRange()
            async let usage = session.apiClient.getUsageStats(range: dateRange, userId: userID)
            async let snapshot = session.apiClient.getDashboardSnapshot(range: dateRange, userId: userID)
            self.usage = try await usage
            let snapshotValue = try await snapshot
            self.trend = snapshotValue.trend ?? []
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }

    private func toggleStatus() async {
        guard let user else { return }
        do {
            self.user = try await session.apiClient.updateUserStatus(userId: userID, status: user.status == "disabled" ? "active" : "disabled")
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }

    private func submitBalance() async {
        guard let value = Double(amount) else {
            errorMessage = "金额格式不正确。"
            return
        }

        do {
            user = try await session.apiClient.updateUserBalance(userId: userID, amount: value, operation: operation, notes: notes.nilIfBlank)
            amount = "10"
            notes = ""
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }
}
