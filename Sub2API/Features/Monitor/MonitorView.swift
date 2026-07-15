import SwiftUI

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published var range: RangeKey = .week
    @Published var settings: AdminSettings?
    @Published var stats: DashboardStats?
    @Published var trend: [TrendPoint] = []
    @Published var models: [ModelStat] = []
    @Published var accounts: [AdminAccount] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(client: APIClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let dateRange = range.dateRange()
        do {
            async let settings = client.getAdminSettings()
            async let stats = client.getDashboardStats()
            async let trend = client.getDashboardTrend(range: dateRange)
            async let models = client.getDashboardModels(range: dateRange)
            async let accounts = client.listAccounts()

            self.settings = try await settings
            self.stats = try await stats
            let trendResult = try await trend
            self.trend = trendResult.trend
            let modelStats = try await models
            self.models = modelStats.models
            let accountPage = try await accounts
            self.accounts = accountPage.items
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }

    var totalAccounts: Int {
        stats?.totalAccounts ?? accounts.count
    }

    var errorAccounts: Int {
        max(stats?.errorAccounts ?? 0, accounts.filter { $0.status == "error" || !($0.errorMessage ?? "").isEmpty }.count)
    }

    var healthyAccounts: Int {
        stats?.normalAccounts ?? max(totalAccounts - errorAccounts, 0)
    }

    var limitedAccounts: Int {
        accounts.filter { account in
            guard let status = account.status?.lowercased() else { return false }
            return status.contains("limit")
        }.count
    }
}

struct MonitorView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel = MonitorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                if viewModel.isLoading && viewModel.stats == nil {
                    LoadingOverlay(message: "正在加载概览数据...")
                } else {
                    content
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, AppLayout.floatingNavContentTopPadding)
            .padding(.bottom, 132)
        }
        .background(Theme.page)
        .overlay(alignment: .top) {
            FloatingNavigationBar(title: "概览") {
                EmptyView()
            } trailing: {
                EmptyView()
            }
        }
        .hideSystemNavigationChrome()
        .refreshable {
            await viewModel.load(client: session.apiClient)
        }
        .task(id: session.activeProfileID) {
            await viewModel.load(client: session.apiClient)
        }
        .onChange(of: viewModel.range) { _ in
            Task { await viewModel.load(client: session.apiClient) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.settings?.siteName?.isEmpty == false ? viewModel.settings?.siteName ?? "管理控制台" : "管理控制台")
                .font(.subheadline)
                .foregroundStyle(Theme.subtext)

            Picker("时间范围", selection: $viewModel.range) {
                ForEach(RangeKey.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard("\(viewModel.range.label) Token", value: AppFormatters.compactNumber(viewModel.trend.reduce(0) { $0 + $1.totalTokens }))
                MetricCard("\(viewModel.range.label) 成本", value: AppFormatters.money(viewModel.trend.reduce(0) { $0 + $1.cost }), tint: Theme.chartViolet)
                MetricCard("今日请求", value: AppFormatters.compactNumber(viewModel.stats?.todayRequests), detail: "RPM \(AppFormatters.compactNumber(viewModel.stats?.rpm))", tint: Theme.chartBlue)
                MetricCard("今日成本", value: AppFormatters.money(viewModel.stats?.todayCost), detail: "TPM \(AppFormatters.compactNumber(viewModel.stats?.tpm))", tint: Theme.warning)
            }

            SectionCard("请求趋势", subtitle: "当前时间范围内的请求变化") {
                if viewModel.trend.count > 1 {
                    SimpleLineChart(points: viewModel.trend, value: { Double($0.requests) }, color: Theme.primary)
                } else {
                    ChartPlaceholder(message: "暂无趋势数据")
                }
            }

            SectionCard("账号健康", subtitle: "总数、健康、限流和异常状态") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricCard("总数", value: AppFormatters.compactNumber(viewModel.totalAccounts))
                    MetricCard("健康", value: AppFormatters.compactNumber(viewModel.healthyAccounts), tint: Theme.success)
                    MetricCard("限流", value: AppFormatters.compactNumber(viewModel.limitedAccounts), tint: Theme.warning)
                    MetricCard("异常", value: AppFormatters.compactNumber(viewModel.errorAccounts), tint: Theme.danger)
                }
            }

            SectionCard("热点模型", subtitle: "按 Token 消耗排序") {
                let topModels = viewModel.models.sorted { $0.totalTokens > $1.totalTokens }.prefix(6)
                if topModels.isEmpty {
                    Text("暂无模型数据")
                        .font(.footnote)
                        .foregroundStyle(Theme.subtext)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(topModels)) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.model)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                    Text("请求 \(AppFormatters.compactNumber(model.requests)) · 成本 \(AppFormatters.money(model.cost))")
                                        .font(.caption)
                                        .foregroundStyle(Theme.subtext)
                                }
                                Spacer()
                                Text(AppFormatters.compactNumber(model.totalTokens))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(12)
                            .background(Theme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
    }
}
