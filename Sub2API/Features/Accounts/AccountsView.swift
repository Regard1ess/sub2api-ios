import SwiftUI

enum AccountFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case paused
    case error

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:
            return "全部"
        case .active:
            return "正常"
        case .paused:
            return "暂停"
        case .error:
            return "异常"
        }
    }
}

@MainActor
final class AccountsViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var filter: AccountFilter = .all
    @Published var accounts: [AdminAccount] = []
    @Published var todayStats: [Int: AccountTodayStats] = [:]
    @Published var feedback: [Int: String] = [:]
    @Published var testingAccountIDs: Set<Int> = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var filteredAccounts: [AdminAccount] {
        accounts.filter { account in
            switch filter {
            case .all:
                return true
            case .active:
                return visualStatus(account).filter == .active
            case .paused:
                return visualStatus(account).filter == .paused
            case .error:
                return visualStatus(account).filter == .error
            }
        }
    }

    func load(client: APIClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await client.listAccounts(search: searchText)
            accounts = page.items
            await loadTodayStats(client: client)
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }

    func test(account: AdminAccount, client: APIClient) async {
        guard !testingAccountIDs.contains(account.id) else { return }
        testingAccountIDs.insert(account.id)
        feedback[account.id] = "测试中..."
        defer { testingAccountIDs.remove(account.id) }

        do {
            try await client.testAccount(accountId: account.id)
            feedback[account.id] = "测试成功"
        } catch {
            if let message = error.userFacingMessage { feedback[account.id] = message } else { feedback[account.id] = nil }
        }

        await load(client: client)
    }

    func toggle(account: AdminAccount, client: APIClient) async {
        let status = visualStatus(account)
        do {
            _ = try await client.setAccountSchedulable(accountId: account.id, schedulable: status.filter == .paused)
            await load(client: client)
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }

    func visualStatus(_ account: AdminAccount) -> (filter: AccountFilter, label: String, tone: StatusPill.Tone) {
        let status = account.status?.lowercased() ?? ""
        if status == "error" || !(account.errorMessage ?? "").isEmpty {
            return (.error, "异常", .danger)
        }
        if ["inactive", "disabled", "paused", "stop", "stopped"].contains(status) || account.schedulable == false {
            return (.paused, "暂停", .neutral)
        }
        return (.active, "正常", .success)
    }

    private func loadTodayStats(client: APIClient) async {
        var next: [Int: AccountTodayStats] = [:]
        await withTaskGroup(of: (Int, AccountTodayStats?).self) { group in
            for account in accounts {
                group.addTask {
                    let stats = try? await client.getAccountTodayStats(accountId: account.id)
                    return (account.id, stats)
                }
            }

            for await (id, stats) in group {
                if let stats {
                    next[id] = stats
                }
            }
        }
        todayStats = next
    }
}

struct AccountsView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel = AccountsViewModel()
    @State private var showingCreateAccount = false

    var body: some View {
        ScreenScroll(topPadding: AppLayout.floatingNavContentTopPadding) {
            SearchField(placeholder: "搜索账号名称 / 平台", text: $viewModel.searchText) {
                Task { await viewModel.load(client: session.apiClient) }
            }

            Picker("状态", selection: $viewModel.filter) {
                ForEach(AccountFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            if viewModel.isLoading && viewModel.accounts.isEmpty {
                LoadingOverlay(message: "正在加载账号...")
            } else if viewModel.filteredAccounts.isEmpty {
                EmptyState(title: "暂无账号", message: "当前筛选条件下没有匹配账号。")
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.filteredAccounts) { account in
                        AccountRow(
                            account: account,
                            status: viewModel.visualStatus(account),
                            today: viewModel.todayStats[account.id],
                            feedback: viewModel.feedback[account.id],
                            isTesting: viewModel.testingAccountIDs.contains(account.id),
                            onTest: { Task { await viewModel.test(account: account, client: session.apiClient) } },
                            onToggle: { Task { await viewModel.toggle(account: account, client: session.apiClient) } }
                        )
                        .padding(14)
                        .surfaceStyle(cornerRadius: 18)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            FloatingNavigationBar(title: "账号") {
                EmptyView()
            } trailing: {
                GlassNavButton(systemImage: "plus") {
                    showingCreateAccount = true
                }
            }
        }
        .hideSystemNavigationChrome()
        .sheet(isPresented: $showingCreateAccount) {
            NavigationStack {
                CreateAccountView {
                    showingCreateAccount = false
                    Task { await viewModel.load(client: session.apiClient) }
                }
            }
        }
        .navigationDestination(for: AdminAccount.self) { account in
            AccountDetailView(account: account) {
                Task { await viewModel.load(client: session.apiClient) }
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

private struct AccountRow: View {
    let account: AdminAccount
    let status: (filter: AccountFilter, label: String, tone: StatusPill.Tone)
    let today: AccountTodayStats?
    let feedback: String?
    let isTesting: Bool
    let onTest: () -> Void
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(account.platform) · \(account.type)")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                Spacer()
                StatusPill(text: status.label, tone: status.tone)
            }

            HStack(spacing: 8) {
                mini("请求", AppFormatters.compactNumber(today?.requests))
                mini("成本", AppFormatters.money(today?.cost))
                mini("Token", AppFormatters.compactNumber(today?.tokens))
            }

            Text("优先级 \(account.priority ?? 0) · 倍率 \(String(format: "%.2f", account.rateMultiplier ?? 1))x · 最近 \(AppFormatters.dateTime(account.lastUsedAt ?? account.updatedAt))")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .lineLimit(2)

            if let errorMessage = account.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
            }

            HStack {
                NavigationLink(value: account) {
                    Text("详情")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(isTesting ? "测试中..." : "测试", action: onTest)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isTesting)
                Button(status.filter == .paused ? "恢复" : "暂停", action: onToggle)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                if let feedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(feedback == "测试成功" ? Theme.success : Theme.subtext)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func mini(_ title: String, _ value: String) -> some View {
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

struct AccountDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var account: AdminAccount
    @State private var today: AccountTodayStats?
    @State private var trend: [TrendPoint] = []
    @State private var feedback: String?
    @State private var isLoading = false
    @State private var isTesting = false
    @State private var isRefreshingAccount = false
    @State private var isDeleting = false
    @State private var showingEditAccount = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    private let onChanged: () -> Void

    init(account: AdminAccount, onChanged: @escaping () -> Void = {}) {
        _account = State(initialValue: account)
        self.onChanged = onChanged
    }

    var body: some View {
        ScreenScroll(topPadding: AppLayout.floatingNavContentTopPadding) {
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }

            SectionCard("账号信息") {
                VStack(spacing: 10) {
                    detailRow("账号 ID", "\(account.id)")
                    detailRow("名称", account.name)
                    detailRow("平台", account.platform)
                    detailRow("类型", account.type)
                    detailRow("状态", visualStatus.label)
                    detailRow("可调度", boolText(account.schedulable))
                    if let notes = account.notes, !notes.isEmpty {
                        detailRow("备注", notes, maxLines: 6)
                    }
                }
            }

            actionSection

            SectionCard("今日统计") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    MetricCard("请求", value: AppFormatters.compactNumber(today?.requests))
                    MetricCard("成本", value: AppFormatters.money(today?.cost), tint: Theme.chartViolet)
                    MetricCard("Token", value: AppFormatters.compactNumber(today?.tokens), tint: Theme.chartBlue)
                }

                VStack(spacing: 10) {
                    detailRow("标准成本", preciseMoney(today?.standardCost))
                    detailRow("用户成本", preciseMoney(today?.userCost))
                    detailRow("实际成本", preciseMoney(today?.cost))
                }
            }

            SectionCard("近 7 天 Token", subtitle: "按当前账号过滤后的用量趋势") {
                if trend.count > 1 {
                    SimpleLineChart(points: trend, value: { Double($0.totalTokens) }, color: Theme.primary)
                } else {
                    ChartPlaceholder(message: "暂无趋势数据")
                }
            }

            SectionCard("调度配置") {
                VStack(spacing: 10) {
                    detailRow("优先级", "\(account.priority ?? 0)")
                    detailRow("最大并发", AppFormatters.compactNumber(account.concurrency))
                    detailRow("当前并发", AppFormatters.compactNumber(account.currentConcurrency))
                    detailRow("倍率", String(format: "%.2f", account.rateMultiplier ?? 1))
                    detailRow("代理 ID", account.proxyId.map(String.init) ?? "--")
                    detailRow("分组 ID", groupIDText)
                }
            }

            SectionCard("分组") {
                if let groups = account.groups, !groups.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(group.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    StatusPill(text: group.status ?? "active", tone: group.status == "active" || group.status == nil ? .success : .neutral)
                                }

                                VStack(spacing: 8) {
                                    detailRow("分组 ID", "\(group.id)")
                                    detailRow("平台", group.platform)
                                    detailRow("倍率", String(format: "%.2f", group.rateMultiplier ?? 1))
                                    detailRow("独占", boolText(group.isExclusive))
                                    detailRow("订阅类型", group.subscriptionType ?? "--")
                                    detailRow("账号数量", AppFormatters.compactNumber(group.accountCount))
                                    detailRow("日限额", preciseMoney(group.dailyLimitUsd))
                                    detailRow("周限额", preciseMoney(group.weeklyLimitUsd))
                                    detailRow("月限额", preciseMoney(group.monthlyLimitUsd))
                                    detailRow("排序", group.sortOrder.map(String.init) ?? "--")
                                    detailRow("更新时间", AppFormatters.dateTime(group.updatedAt))
                                }
                            }
                            .padding(10)
                            .background(Theme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                } else {
                    Text("未绑定分组")
                        .font(.footnote)
                        .foregroundStyle(Theme.subtext)
                }
            }

            SectionCard("时间信息") {
                VStack(spacing: 10) {
                    detailRow("创建时间", AppFormatters.dateTime(account.createdAt))
                    detailRow("更新时间", AppFormatters.dateTime(account.updatedAt))
                    detailRow("最近使用", AppFormatters.dateTime(account.lastUsedAt))
                }
            }

            if !extraEntries.isEmpty {
                SectionCard("扩展参数") {
                    VStack(spacing: 10) {
                        ForEach(extraEntries, id: \.key) { entry in
                            detailRow(entry.label, entry.value, maxLines: 8)
                        }
                    }
                }
            }

            if let error = account.errorMessage, !error.isEmpty {
                SectionCard("异常信息") {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .textSelection(.enabled)
                }
            }

        }
        .overlay(alignment: .top) {
            FloatingNavigationBar(title: account.name) {
                GlassNavButton(systemImage: "chevron.left") {
                    dismiss()
                }
            } trailing: {
                GlassNavButton(systemImage: "square.and.pencil") {
                    showingEditAccount = true
                }
            }
        }
        .hideSystemNavigationChrome()
        .sheet(isPresented: $showingEditAccount) {
            NavigationStack {
                EditAccountView(account: account) { updatedAccount in
                    account = updatedAccount
                    showingEditAccount = false
                    onChanged()
                }
            }
        }
        .alert("删除账号", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("将永久删除「\(account.name)」，删除后不可恢复。")
        }
        .refreshable {
            await load()
        }
        .task(id: account.id) {
            await load()
        }
    }

    private var actionSection: some View {
        SectionCard("操作") {
            VStack(spacing: 10) {
                HStack {
                    Button(isTesting ? "测试中..." : "测试账号") {
                        Task { await testAccount() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting)
                    .frame(maxWidth: .infinity)

                    Button(isRefreshingAccount ? "刷新中..." : "刷新凭据") {
                        Task { await refreshAccount() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshingAccount)
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    Button(visualStatus.filter == .paused ? "恢复调度" : "暂停调度") {
                        Task { await toggleSchedulable() }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("编辑资料") {
                        showingEditAccount = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }

                Button(isDeleting ? "删除中" : "删除账号", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.danger)
                .disabled(isDeleting)
                .frame(maxWidth: .infinity)

                if let feedback {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundStyle(feedback == "测试成功" ? Theme.success : Theme.subtext)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var visualStatus: (filter: AccountFilter, label: String, tone: StatusPill.Tone) {
        let status = account.status?.lowercased() ?? ""
        if status == "error" || !(account.errorMessage ?? "").isEmpty {
            return (.error, "异常", .danger)
        }
        if ["inactive", "disabled", "paused", "stop", "stopped"].contains(status) || account.schedulable == false {
            return (.paused, "暂停", .neutral)
        }
        return (.active, "正常", .success)
    }

    private var groupIDText: String {
        let ids = account.groupIds ?? account.groups?.map(\.id) ?? []
        return ids.isEmpty ? "--" : ids.map { String($0) }.joined(separator: ", ")
    }

    private var extraEntries: [(key: String, label: String, value: String)] {
        (account.extra ?? [:])
            .compactMap { key, value in
                let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedKey.isEmpty,
                      !normalizedKey.isDeprecatedCodex5hKey,
                      let filteredValue = value.removingDeprecatedCodex5hValues else {
                    return nil
                }
                return (
                    key: normalizedKey,
                    label: AccountExtraDisplayName.label(
                        for: normalizedKey,
                        platform: account.platform,
                        type: account.type
                    ),
                    value: AccountExtraValueFormatter.displayText(for: filteredValue, key: normalizedKey)
                )
            }
            .sorted {
                let result = $0.label.localizedStandardCompare($1.label)
                return result == .orderedSame ? $0.key < $1.key : result == .orderedAscending
            }
    }

    private func detailRow(_ label: String, _ value: String, maxLines: Int = 3) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .foregroundStyle(Theme.subtext)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(maxLines)
        }
        .font(.subheadline)
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else { return "--" }
        return value ? "是" : "否"
    }

    private func preciseMoney(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "$%.4f", value)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let nextAccount = session.apiClient.getAccount(account.id)
            async let nextToday = session.apiClient.getAccountTodayStats(accountId: account.id)
            async let nextTrend = session.apiClient.getDashboardTrend(range: RangeKey.week.dateRange(), accountId: account.id)
            account = try await nextAccount
            today = try await nextToday
            trend = (try? await nextTrend)?.trend ?? []
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }

    private func testAccount() async {
        guard !isTesting else { return }
        isTesting = true
        feedback = "测试中..."
        defer { isTesting = false }

        do {
            try await session.apiClient.testAccount(accountId: account.id)
            feedback = "测试成功"
            await load()
            onChanged()
        } catch {
            if let message = error.userFacingMessage { feedback = message } else { feedback = nil }
            await load()
            onChanged()
        }
    }

    private func refreshAccount() async {
        guard !isRefreshingAccount else { return }
        isRefreshingAccount = true
        feedback = "刷新中..."
        defer { isRefreshingAccount = false }

        do {
            try await session.apiClient.refreshAccount(accountId: account.id)
            feedback = "刷新完成"
            await load()
            onChanged()
        } catch {
            if let message = error.userFacingMessage { feedback = message } else { feedback = nil }
        }
    }

    private func toggleSchedulable() async {
        do {
            account = try await session.apiClient.setAccountSchedulable(accountId: account.id, schedulable: visualStatus.filter == .paused)
            onChanged()
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await session.apiClient.deleteAccount(account.id)
            onChanged()
            dismiss()
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }
}

private enum AccountExtraDisplayName {
    static func label(for key: String, platform: String, type: String) -> String {
        let lookupKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let platformKey = platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let typeKey = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let accountTypeKey = "\(platformKey):\(typeKey)"

        if let label = accountTypeLabels[accountTypeKey]?[lookupKey] {
            return label
        }
        if let label = platformLabels[platformKey]?[lookupKey] {
            return label
        }
        if let label = typeLabels[typeKey]?[lookupKey] {
            return label
        }
        if let label = commonLabels[lookupKey] {
            return label
        }
        return fallbackLabel(for: lookupKey)
    }

    private static let commonLabels: [String: String] = [
        "account_uuid": "账号 UUID",
        "active_until": "有效期至",
        "activated_at": "激活时间",
        "ai_credits": "AI Credits",
        "allow_overages": "允许超量请求",
        "auto_pause_5h_disabled": "禁用 5h 自动暂停",
        "auto_pause_5h_threshold": "5h 用量暂停阈值",
        "auto_pause_7d_disabled": "禁用 7d 自动暂停",
        "auto_pause_7d_threshold": "7d 用量暂停阈值",
        "base_rpm": "基础 RPM",
        "cache_ttl_override_enabled": "缓存 TTL 强制替换",
        "cache_ttl_override_target": "缓存 TTL 目标",
        "codex_7d_reset_after_seconds": "Codex 7d 重置剩余秒数",
        "codex_7d_reset_at": "Codex 7d 重置时间",
        "codex_7d_used_percent": "Codex 7d 用量百分比",
        "codex_7d_window_minutes": "Codex 7d 窗口分钟数",
        "codex_primary_over_secondary_percent": "Codex 主/备用窗口用量百分比",
        "codex_primary_reset_after_seconds": "Codex 主窗口重置剩余秒数",
        "codex_primary_used_percent": "Codex 主窗口用量百分比",
        "codex_primary_window_minutes": "Codex 主窗口分钟数",
        "codex_secondary_reset_after_seconds": "Codex 备用窗口重置剩余秒数",
        "codex_secondary_used_percent": "Codex 备用窗口用量百分比",
        "codex_secondary_window_minutes": "Codex 备用窗口分钟数",
        "codex_usage_updated_at": "Codex 用量更新时间",
        "custom_base_url": "自定义转发地址",
        "custom_base_url_enabled": "启用自定义转发地址",
        "email": "邮箱地址",
        "email_address": "邮箱地址",
        "enable_tls_fingerprint": "TLS 指纹模拟",
        "entitlement_status": "权益状态",
        "load_code_assist": "Code Assist 额度",
        "max_sessions": "最大会话数",
        "mixed_scheduling": "参与 /v1/messages 调度",
        "model_rate_limits": "模型级限流",
        "name": "用户名称",
        "org_uuid": "组织 UUID",
        "privacy_mode": "隐私模式",
        "quota_daily_limit": "日额度限制",
        "quota_daily_reset_at": "日额度下次重置",
        "quota_daily_reset_hour": "日额度重置小时",
        "quota_daily_reset_mode": "日额度重置模式",
        "quota_daily_start": "日额度窗口开始",
        "quota_daily_used": "日额度已用",
        "quota_limit": "总额度限制",
        "quota_reset_timezone": "额度重置时区",
        "quota_used": "总额度已用",
        "quota_weekly_limit": "周额度限制",
        "quota_weekly_reset_at": "周额度下次重置",
        "quota_weekly_reset_day": "周额度重置星期",
        "quota_weekly_reset_hour": "周额度重置小时",
        "quota_weekly_reset_mode": "周额度重置模式",
        "quota_weekly_start": "周额度窗口开始",
        "quota_weekly_used": "周额度已用",
        "rate_limit_reset_at": "限流恢复时间",
        "rate_limited_at": "限流时间",
        "rpm_sticky_buffer": "RPM 粘性缓冲区",
        "rpm_strategy": "RPM 策略",
        "session_id_masking_enabled": "会话 ID 伪装",
        "session_idle_timeout_minutes": "会话空闲超时",
        "subscription_tier": "订阅档位",
        "subscription_tier_raw": "订阅档位原始值",
        "tls_fingerprint_profile_id": "TLS 指纹配置",
        "today_cost": "今日标准计费",
        "user_msg_queue_enabled": "用户消息队列（旧）",
        "user_msg_queue_mode": "用户消息限速模式",
        "window_cost_limit": "5h 窗口费用阈值",
        "window_cost_sticky_reserve": "粘性预留额度"
    ]

    private static let platformLabels: [String: [String: String]] = [
        "antigravity": [
            "allow_overages": "允许 AI Credits 超量请求",
            "antigravity_credits_overages": "AI Credits 超量窗口",
            "load_code_assist": "Code Assist 额度",
            "mixed_scheduling": "参与 /v1/messages 调度",
            "privacy_mode": "Antigravity 隐私状态"
        ],
        "anthropic": [
            "anthropic_apikey_auth_scheme": "上游认证方式",
            "anthropic_passthrough": "Anthropic 自动透传",
            "web_search_emulation": "Web Search 模拟"
        ],
        "bedrock": [
            "quota_limit": "Bedrock 总额度限制",
            "quota_daily_limit": "Bedrock 日额度限制",
            "quota_weekly_limit": "Bedrock 周额度限制"
        ],
        "gemini": [
            "gemini_flash_daily": "Gemini Flash 日额度",
            "gemini_flash_minute": "Gemini Flash 分钟额度",
            "gemini_pro_daily": "Gemini Pro 日额度",
            "gemini_pro_minute": "Gemini Pro 分钟额度",
            "gemini_shared_daily": "Gemini 共享日额度",
            "gemini_shared_minute": "Gemini 共享分钟额度",
            "load_code_assist": "Code Assist 额度"
        ],
        "grok": [
            "email": "Grok 邮箱",
            "entitlement_status": "Grok 权益状态",
            "grok_billing": "Grok 账单摘要",
            "grok_billing_snapshot": "Grok 账单快照",
            "grok_entitlement_status": "Grok 权益状态",
            "grok_last_headers_seen_at": "Grok 最近额度头时间",
            "grok_last_quota_probe_at": "Grok 最近额度探测",
            "grok_last_status_code": "Grok 最近状态码",
            "grok_local_usage": "Grok 本地用量",
            "grok_local_usage_24h": "Grok 24h 本地用量",
            "grok_local_usage_7d": "Grok 7d 本地用量",
            "grok_local_usage_monthly": "Grok 月度本地用量",
            "grok_quota_snapshot": "Grok 额度快照",
            "grok_quota_snapshot_state": "Grok 额度快照状态",
            "grok_request_quota": "Grok 请求额度",
            "grok_retry_after_seconds": "Grok 重试等待秒数",
            "grok_token_quota": "Grok Token 额度",
            "subscription_tier": "Grok 订阅档位",
            "subscription_tier_raw": "Grok 订阅档位原始值"
        ],
        "openai": [
            "codex_cli_only": "仅允许 Codex 官方客户端",
            "codex_cli_only_allow_app_server": "允许 Codex app-server 客户端",
            "codex_cli_only_allowed_clients": "Codex 允许客户端（旧）",
            "codex_image_generation_bridge": "Codex 图片工具注入",
            "codex_image_generation_bridge_enabled": "Codex 图片工具注入（旧）",
            "codex_image_generation_explicit_tool_policy": "Codex 图片工具策略",
            "email": "OpenAI 邮箱",
            "name": "OpenAI 用户名称",
            "openai_apikey_responses_websockets_v2_enabled": "API Key WebSocket Mode 启用",
            "openai_apikey_responses_websockets_v2_mode": "API Key WebSocket Mode",
            "openai_compact_checked_at": "Compact 最近探测",
            "openai_compact_last_error": "Compact 最近错误",
            "openai_compact_last_status": "Compact 最近状态码",
            "openai_compact_mode": "Compact 模式",
            "openai_compact_supported": "支持 Compact",
            "openai_long_context_billing_enabled": "API 长上下文计费",
            "openai_oauth_passthrough": "OpenAI OAuth 自动透传",
            "openai_oauth_responses_websockets_v2_enabled": "OAuth WebSocket Mode 启用",
            "openai_oauth_responses_websockets_v2_mode": "OAuth WebSocket Mode",
            "openai_passthrough": "OpenAI 自动透传",
            "openai_responses_mode": "Responses API 模式",
            "openai_responses_supported": "Responses API 支持状态",
            "openai_ws_enabled": "OpenAI WebSocket 启用（旧）",
            "privacy_mode": "OpenAI 隐私模式",
            "responses_websockets_v2_enabled": "Responses WebSocket v2 启用（旧）"
        ],
        "spark": [
            "parent_chatgpt_account_id": "母账号 ChatGPT ID",
            "parent_email": "母账号邮箱",
            "parent_plan_type": "母账号订阅档位",
            "parent_privacy_mode": "母账号隐私模式",
            "parent_subscription_expires_at": "母账号订阅过期时间",
            "quota_dimension": "额度维度"
        ]
    ]

    private static let accountTypeLabels: [String: [String: String]] = [
        "anthropic:apikey": [
            "anthropic_apikey_auth_scheme": "上游认证方式",
            "anthropic_passthrough": "API Key 自动透传",
            "web_search_emulation": "Web Search 模拟"
        ],
        "openai:apikey": [
            "openai_apikey_responses_websockets_v2_enabled": "API Key WebSocket Mode 启用",
            "openai_apikey_responses_websockets_v2_mode": "API Key WebSocket Mode",
            "openai_long_context_billing_enabled": "API 长上下文计费",
            "openai_passthrough": "API Key 自动透传",
            "openai_responses_mode": "Responses API 模式",
            "openai_responses_supported": "Responses API 支持状态"
        ],
        "openai:oauth": [
            "codex_cli_only": "仅允许 Codex 官方客户端",
            "codex_cli_only_allow_app_server": "允许 Codex app-server 客户端",
            "openai_oauth_passthrough": "OAuth 自动透传",
            "openai_oauth_responses_websockets_v2_enabled": "OAuth WebSocket Mode 启用",
            "openai_oauth_responses_websockets_v2_mode": "OAuth WebSocket Mode",
            "privacy_mode": "ChatGPT 隐私模式"
        ]
    ]

    private static let typeLabels: [String: [String: String]] = [
        "oauth": [
            "account_uuid": "OAuth 账号 UUID",
            "email_address": "OAuth 邮箱",
            "org_uuid": "OAuth 组织 UUID"
        ]
    ]

    private static let fallbackTokens: [String: String] = [
        "account": "账号",
        "active": "活跃",
        "api": "API",
        "apikey": "API Key",
        "at": "时间",
        "auth": "认证",
        "base": "基础",
        "billing": "账单",
        "cache": "缓存",
        "capabilities": "能力",
        "code": "状态码",
        "compact": "Compact",
        "cost": "费用",
        "daily": "日",
        "enabled": "启用",
        "error": "错误",
        "expires": "过期",
        "fingerprint": "指纹",
        "limit": "限制",
        "mode": "模式",
        "oauth": "OAuth",
        "percent": "百分比",
        "quota": "额度",
        "rate": "速率",
        "reset": "重置",
        "responses": "Responses",
        "rpm": "RPM",
        "session": "会话",
        "status": "状态",
        "supported": "支持",
        "tls": "TLS",
        "usage": "用量",
        "used": "已用",
        "weekly": "周",
        "window": "窗口"
    ]

    private static func fallbackLabel(for key: String) -> String {
        let words = key
            .split(separator: "_")
            .map { part in
                let token = String(part)
                return fallbackTokens[token] ?? token
            }
        return words.isEmpty ? "扩展参数" : words.joined(separator: " ")
    }
}

private enum AccountExtraValueFormatter {
    static func displayText(for value: JSONValue, key: String) -> String {
        guard key.isPercentExtraKey, let percentText = percentText(for: value) else {
            return value.displayText
        }
        return percentText
    }

    private static func percentText(for value: JSONValue) -> String? {
        switch value {
        case .number(let number):
            return "\(trimmedNumber(number))%"
        case .string(let rawValue):
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            if value.hasSuffix("%") { return value }
            guard let number = Double(value) else { return nil }
            return "\(trimmedNumber(number))%"
        case .bool, .object, .array, .null:
            return nil
        }
    }

    private static func trimmedNumber(_ value: Double) -> String {
        guard value.isFinite else { return String(format: "%g", value) }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000001 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

private extension JSONValue {
    var removingDeprecatedCodex5hValues: JSONValue? {
        switch self {
        case .object(let values):
            let filtered = values.compactMapValues { value in
                value.removingDeprecatedCodex5hValues
            }
            .filter { key, _ in !key.isDeprecatedCodex5hKey }
            return filtered.isEmpty ? nil : .object(filtered)
        case .array(let values):
            let filtered = values.compactMap { $0.removingDeprecatedCodex5hValues }
            return filtered.isEmpty ? nil : .array(filtered)
        case .string(let value):
            return value.isDeprecatedCodex5hKey ? nil : self
        case .number, .bool, .null:
            return self
        }
    }

    var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(format: "%g", value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object, .array:
            if let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "--"
        case .null:
            return "null"
        }
    }
}

private extension String {
    var isDeprecatedCodex5hKey: Bool {
        localizedCaseInsensitiveContains("codex_5h")
    }

    var isPercentExtraKey: Bool {
        let key = lowercased()
        return key.hasSuffix("_percent") || key.contains("_percent_")
    }
}

private enum AccountFormInputStyle {
    case text
    case secure
    case multiline(ClosedRange<Int>)
}

private struct AccountFormField: View {
    let title: String
    @Binding var text: String
    var style: AccountFormInputStyle = .text
    var keyboardType: UIKeyboardType = .default
    var textInputAutocapitalization: TextInputAutocapitalization? = nil
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.subtext)

            input
                .font(monospaced ? Font.system(.body, design: .monospaced) : .body)
                .foregroundStyle(Theme.text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(textInputAutocapitalization)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .tint(Theme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(minHeight: fieldMinHeight, alignment: .topLeading)
                .background(Theme.formField)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.formFieldBorder, lineWidth: 0.9)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(title)
        }
        .padding(.vertical, 3)
    }

    private var fieldMinHeight: CGFloat {
        switch style {
        case .text, .secure:
            return 46
        case .multiline:
            return 96
        }
    }

    @ViewBuilder
    private var input: some View {
        switch style {
        case .text:
            TextField("", text: $text)
        case .secure:
            SecureField("", text: $text)
        case .multiline(let lineLimit):
            TextField("", text: $text, axis: .vertical)
                .lineLimit(lineLimit)
        }
    }
}

struct EditAccountView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    private let account: AdminAccount
    let onSaved: (AdminAccount) -> Void

    @State private var name: String
    @State private var notes: String
    @State private var platform: String
    @State private var type: String
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var accessToken = ""
    @State private var refreshToken = ""
    @State private var clientID = ""
    @State private var concurrency: String
    @State private var priority: String
    @State private var rateMultiplier: String
    @State private var proxyID: String
    @State private var groupIDs: String
    @State private var extraCredentialsJSON = ""
    @State private var extraJSON = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let platforms = ["anthropic", "openai", "gemini", "sora", "antigravity"]
    private let types = ["apikey", "oauth"]

    init(account: AdminAccount, onSaved: @escaping (AdminAccount) -> Void) {
        self.account = account
        self.onSaved = onSaved
        _name = State(initialValue: account.name)
        _notes = State(initialValue: account.notes ?? "")
        _platform = State(initialValue: account.platform)
        _type = State(initialValue: account.type)
        _concurrency = State(initialValue: account.concurrency.map { String($0) } ?? "")
        _priority = State(initialValue: account.priority.map { String($0) } ?? "")
        _rateMultiplier = State(initialValue: account.rateMultiplier.map { String($0) } ?? "")
        _proxyID = State(initialValue: account.proxyId.map { String($0) } ?? "")
        let ids = account.groupIds ?? account.groups?.map(\.id) ?? []
        _groupIDs = State(initialValue: ids.map { String($0) }.joined(separator: ","))
    }

    var body: some View {
        Form {
            Section("基础配置") {
                AccountFormField(title: "账号名称", text: $name)
                Picker("平台", selection: $platform) {
                    ForEach(platforms, id: \.self) { Text($0).tag($0) }
                }
                Picker("类型", selection: $type) {
                    ForEach(types, id: \.self) { Text($0.uppercased()).tag($0) }
                }
                AccountFormField(title: "备注", text: $notes)
            }

            Section("凭证变更") {
                if type == "apikey" {
                    AccountFormField(
                        title: "Base URL（留空不修改）",
                        text: $baseURL,
                        keyboardType: .URL,
                        textInputAutocapitalization: .never
                    )
                    AccountFormField(title: "API Key（留空不修改）", text: $apiKey, style: .secure)
                } else {
                    AccountFormField(title: "Access Token（留空不修改）", text: $accessToken, style: .secure)
                    AccountFormField(title: "Refresh Token（留空不修改）", text: $refreshToken, style: .secure)
                    AccountFormField(title: "Client ID（留空不修改）", text: $clientID)
                }
                AccountFormField(
                    title: "额外凭证 JSON（可选）",
                    text: $extraCredentialsJSON,
                    style: .multiline(3...8),
                    monospaced: true
                )
            }

            Section("高级参数") {
                AccountFormField(title: "并发", text: $concurrency, keyboardType: .numberPad)
                AccountFormField(title: "优先级", text: $priority, keyboardType: .numberPad)
                AccountFormField(title: "倍率", text: $rateMultiplier, keyboardType: .decimalPad)
                AccountFormField(title: "代理 ID", text: $proxyID, keyboardType: .numberPad)
                AccountFormField(title: "分组 IDs，逗号分隔", text: $groupIDs)
                AccountFormField(
                    title: "extra JSON（可选）",
                    text: $extraJSON,
                    style: .multiline(3...8),
                    monospaced: true
                )
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
            FloatingNavigationBar(title: "编辑账号") {
                GlassNavButton(systemImage: "xmark") {
                    dismiss()
                }
            } trailing: {
                GlassNavButton(
                    systemImage: isSaving ? "hourglass" : "checkmark",
                    isDisabled: isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            var credentials = try FormParser.parseFlatJSONObject(extraCredentialsJSON, fieldName: "额外凭证") ?? [:]
            if type == "apikey" {
                if let baseURL = baseURL.nilIfBlank {
                    credentials["base_url"] = .string(baseURL)
                }
                if let apiKey = apiKey.nilIfBlank {
                    credentials["api_key"] = .string(apiKey)
                }
            } else {
                if let accessToken = accessToken.nilIfBlank {
                    credentials["access_token"] = .string(accessToken)
                }
                if let refreshToken = refreshToken.nilIfBlank {
                    credentials["refresh_token"] = .string(refreshToken)
                }
                if let clientID = clientID.nilIfBlank {
                    credentials["client_id"] = .string(clientID)
                }
            }

            let groups = try parseGroupIDs(groupIDs)
            let payload = UpdateAccountPayload(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                platform: platform,
                type: type,
                credentials: credentials.isEmpty ? nil : credentials,
                extra: try FormParser.parseFlatJSONObject(extraJSON, fieldName: "extra"),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                proxyId: try parseOptionalInt(proxyID, fieldName: "代理 ID"),
                concurrency: try parseOptionalInt(concurrency, fieldName: "并发"),
                priority: try parseOptionalInt(priority, fieldName: "优先级"),
                rateMultiplier: try parseOptionalDouble(rateMultiplier, fieldName: "倍率"),
                groupIds: groups
            )
            let updated = try await session.apiClient.updateAccount(account.id, payload: payload)
            onSaved(updated)
            dismiss()
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }

    private func parseGroupIDs(_ raw: String) throws -> [Int] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return try trimmed.split(separator: ",").map { part in
            let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = Int(value) else {
                throw APIError.requestFailed("分组 ID 必须是数字。")
            }
            return id
        }
    }

    private func parseOptionalInt(_ raw: String, fieldName: String) throws -> Int? {
        guard let value = raw.nilIfBlank else { return nil }
        guard let parsed = Int(value) else {
            throw APIError.requestFailed("\(fieldName) 必须是数字。")
        }
        return parsed
    }

    private func parseOptionalDouble(_ raw: String, fieldName: String) throws -> Double? {
        guard let value = raw.nilIfBlank else { return nil }
        guard let parsed = Double(value) else {
            throw APIError.requestFailed("\(fieldName) 必须是数字。")
        }
        return parsed
    }
}

struct CreateAccountView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var platform = "anthropic"
    @State private var type = "apikey"
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var accessToken = ""
    @State private var refreshToken = ""
    @State private var clientID = ""
    @State private var concurrency = ""
    @State private var priority = ""
    @State private var rateMultiplier = ""
    @State private var proxyID = ""
    @State private var groupIDs = ""
    @State private var extraCredentialsJSON = ""
    @State private var extraJSON = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    let onSaved: () -> Void

    private let platforms = ["anthropic", "openai", "gemini", "sora", "antigravity"]
    private let types = ["apikey", "oauth"]

    var body: some View {
        Form {
            Section("基础配置") {
                AccountFormField(title: "账号名称", text: $name)
                Picker("平台", selection: $platform) {
                    ForEach(platforms, id: \.self) { Text($0).tag($0) }
                }
                Picker("类型", selection: $type) {
                    ForEach(types, id: \.self) { Text($0.uppercased()).tag($0) }
                }
                AccountFormField(title: "备注（可选）", text: $notes)
            }

            Section("凭证") {
                if type == "apikey" {
                    AccountFormField(
                        title: "Base URL",
                        text: $baseURL,
                        keyboardType: .URL,
                        textInputAutocapitalization: .never
                    )
                    AccountFormField(title: "API Key", text: $apiKey, style: .secure)
                } else {
                    AccountFormField(title: "Access Token", text: $accessToken, style: .secure)
                    AccountFormField(title: "Refresh Token（可选）", text: $refreshToken, style: .secure)
                    AccountFormField(title: "Client ID（可选）", text: $clientID)
                }
                AccountFormField(
                    title: "额外凭证 JSON（可选）",
                    text: $extraCredentialsJSON,
                    style: .multiline(3...8),
                    monospaced: true
                )
            }

            Section("高级参数") {
                AccountFormField(title: "并发", text: $concurrency, keyboardType: .numberPad)
                AccountFormField(title: "优先级", text: $priority, keyboardType: .numberPad)
                AccountFormField(title: "倍率", text: $rateMultiplier, keyboardType: .decimalPad)
                AccountFormField(title: "代理 ID", text: $proxyID, keyboardType: .numberPad)
                AccountFormField(title: "分组 IDs，逗号分隔", text: $groupIDs)
                AccountFormField(
                    title: "extra JSON（可选）",
                    text: $extraJSON,
                    style: .multiline(3...8),
                    monospaced: true
                )
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
            FloatingNavigationBar(title: "添加账号") {
                GlassNavButton(systemImage: "xmark") {
                    dismiss()
                }
            } trailing: {
                GlassNavButton(
                    systemImage: isSaving ? "hourglass" : "checkmark",
                    isDisabled: isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !credentialReady
                ) {
                    Task { await save() }
                }
            }
        }
        .hideSystemNavigationChrome()
    }

    private var credentialReady: Bool {
        type == "apikey" ? (!baseURL.isEmpty && !apiKey.isEmpty) : !accessToken.isEmpty
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            var credentials = try FormParser.parseFlatJSONObject(extraCredentialsJSON, fieldName: "额外凭证") ?? [:]
            if type == "apikey" {
                credentials["base_url"] = .string(baseURL)
                credentials["api_key"] = .string(apiKey)
            } else {
                credentials["access_token"] = .string(accessToken)
                if let refreshToken = refreshToken.nilIfBlank {
                    credentials["refresh_token"] = .string(refreshToken)
                }
                if let clientID = clientID.nilIfBlank {
                    credentials["client_id"] = .string(clientID)
                }
            }

            let groups = groupIDs
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

            let payload = CreateAccountPayload(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                platform: platform,
                type: type,
                credentials: credentials,
                extra: try FormParser.parseFlatJSONObject(extraJSON, fieldName: "extra"),
                notes: notes.nilIfBlank,
                proxyId: Int(proxyID),
                concurrency: Int(concurrency),
                priority: Int(priority),
                rateMultiplier: Double(rateMultiplier),
                groupIds: groups.isEmpty ? nil : groups
            )
            _ = try await session.apiClient.createAccount(payload)
            onSaved()
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }
}
