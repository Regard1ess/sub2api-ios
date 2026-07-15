import SwiftUI

@MainActor
final class GroupsViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var groups: [AdminGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(client: APIClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await client.listGroups(search: searchText)
            groups = page.items
        } catch {
            if let message = error.userFacingMessage { errorMessage = message }
        }
    }
}

struct GroupsView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel = GroupsViewModel()

    var body: some View {
        ScreenScroll(topPadding: AppLayout.floatingNavContentTopPadding) {
            SearchField(placeholder: "搜索分组名称", text: $viewModel.searchText) {
                Task { await viewModel.load(client: session.apiClient) }
            }

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            if viewModel.isLoading && viewModel.groups.isEmpty {
                LoadingOverlay(message: "正在加载分组...")
            } else if viewModel.groups.isEmpty {
                EmptyState(title: "暂无分组", message: "连接 Sub2API 后，这里会展示分组与调度归属。")
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.groups) { group in
                        GroupRow(group: group)
                            .padding(14)
                            .surfaceStyle(cornerRadius: 18)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            FloatingNavigationBar(title: "分组") {
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
    }
}

private struct GroupRow: View {
    let group: AdminGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text("\(group.platform) · 倍率 \(String(format: "%.2f", group.rateMultiplier ?? 1)) · \(group.subscriptionType ?? "standard")")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                        .lineLimit(1)
                }
                Spacer()
                StatusPill(text: group.status ?? "active", tone: group.status == "active" || group.status == nil ? .success : .neutral)
            }

            Text("账号数 \(group.accountCount ?? 0) · \(group.isExclusive == true ? "独占分组" : "共享分组")")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
        .padding(.vertical, 6)
    }
}
