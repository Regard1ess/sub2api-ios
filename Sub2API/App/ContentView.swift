import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: SessionStore
    private let authAnimation = Animation.spring(response: 0.44, dampingFraction: 0.88, blendDuration: 0.12)

    var body: some View {
        ZStack {
            if !session.isHydrated {
                ProgressView()
                    .tint(Theme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.page)
                    .transition(.opacity)
            } else if session.isAuthenticated {
                RootShellView()
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.985)),
                            removal: .opacity.combined(with: .move(edge: .bottom))
                        )
                    )
            } else {
                LoginView()
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.965)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        )
                    )
            }
        }
        .tint(Theme.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page.ignoresSafeArea())
        .animation(authAnimation, value: session.isHydrated)
        .animation(authAnimation, value: session.isAuthenticated)
    }
}

private struct RootShellView: View {
    @State private var selectedTab: AppTab = .monitor
    @State private var previousTab: AppTab = .monitor
    @State private var tabDirection: CGFloat = 1
    @State private var visitedTabs: Set<AppTab> = [.monitor]
    private let tabAnimation = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.92, blendDuration: 0.12)

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                ZStack {
                    ForEach(AppTab.allCases) { tab in
                        if visitedTabs.contains(tab) {
                            tabContent(tab)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .opacity(tabOpacity(tab))
                                .offset(x: tabOffset(tab, width: proxy.size.width))
                                .allowsHitTesting(selectedTab == tab)
                                .accessibilityHidden(selectedTab != tab)
                                .zIndex(tabZIndex(tab))
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 84)
            }

            FloatingGlassTabBar(selectedTab: tabSelection)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .background(Theme.page.ignoresSafeArea())
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { selectTab($0) }
        )
    }

    private func selectTab(_ tab: AppTab) {
        guard tab != selectedTab else { return }
        let oldTab = selectedTab
        tabDirection = tab.index > oldTab.index ? 1 : -1
        previousTab = oldTab
        visitedTabs.insert(tab)

        DispatchQueue.main.async {
            withAnimation(tabAnimation) {
                selectedTab = tab
            }
        }
    }

    private func tabOffset(_ tab: AppTab, width: CGFloat) -> CGFloat {
        guard tab != selectedTab else { return 0 }
        if tab == previousTab {
            return -tabDirection * width
        }
        return tab.index < selectedTab.index ? -width : width
    }

    private func tabOpacity(_ tab: AppTab) -> Double {
        tab == selectedTab || tab == previousTab ? 1 : 0
    }

    private func tabZIndex(_ tab: AppTab) -> Double {
        if tab == selectedTab { return 2 }
        if tab == previousTab { return 1 }
        return 0
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .monitor:
            NavigationStack {
                MonitorView()
            }
        case .users:
            NavigationStack {
                UsersView()
            }
        case .accounts:
            NavigationStack {
                AccountsView()
            }
        case .groups:
            NavigationStack {
                GroupsView()
            }
        case .settings:
            NavigationStack {
                SettingsView()
            }
        }
    }
}

private enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case monitor
    case users
    case accounts
    case groups
    case settings

    var id: String { rawValue }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var title: String {
        switch self {
        case .monitor:
            return "概览"
        case .users:
            return "用户"
        case .accounts:
            return "账号"
        case .groups:
            return "分组"
        case .settings:
            return "服务器"
        }
    }

    var systemImage: String {
        switch self {
        case .monitor:
            return "chart.line.uptrend.xyaxis"
        case .users:
            return "person.2"
        case .accounts:
            return "key"
        case .groups:
            return "folder"
        case .settings:
            return "server.rack"
        }
    }
}

private struct FloatingGlassTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    tabItem(tab)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Theme.glassBorderStrong.opacity(0.78),
                            Theme.glassBorderSoft.opacity(0.72),
                            Theme.border.opacity(0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(Theme.glassHairline)
                .frame(height: 1)
                .padding(.horizontal, 28)
        }
    }

    private func tabItem(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return VStack(spacing: 5) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Theme.primary.opacity(0.10))
                        .matchedGeometryEffect(id: "selected-glow", in: selectionNamespace)
                        .frame(width: 34, height: 34)
                        .blur(radius: 8)
                }

                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Theme.primary : Theme.subtext)
                    .scaleEffect(isSelected ? 1.06 : 1)
                    .frame(height: 32)
            }
            .frame(height: 34)

            Text(tab.title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.primary : Theme.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            ZStack {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Theme.primary.opacity(0.68))
                        .matchedGeometryEffect(id: "selected-indicator", in: selectionNamespace)
                        .frame(width: 18, height: 3)
                } else {
                    Color.clear.frame(width: 18, height: 3)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
