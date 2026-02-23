//
//  ContentView.swift
//  tmTrackerExample
//
//  Created by Alban Elshani on 12.2.26.
//

import SwiftUI

enum MainTab: String, CaseIterable {
    case portfolio = "Portfolio"
    case swap = "Swap"
    case explore = "Explore"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .portfolio: return "chart.pie.fill"
        case .swap: return "arrow.left.arrow.right"
        case .explore: return "safari"
        case .settings: return "gearshape.fill"
        }
    }

    var pageUrl: String { "ios://\(rawValue.lowercased())" }
    var pageTitle: String { rawValue }
}

struct ContentView: View {
    @State private var selectedTab: MainTab = .portfolio
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PortfolioPageView()
                    .heatmapGesture()
            }
            .tabItem {
                Label(MainTab.portfolio.rawValue, systemImage: MainTab.portfolio.icon)
            }
            .tag(MainTab.portfolio)

            NavigationStack {
                SwapPageView()
                    .heatmapGesture()
            }
            .tabItem {
                Label(MainTab.swap.rawValue, systemImage: MainTab.swap.icon)
            }
            .tag(MainTab.swap)

            NavigationStack {
                ExplorePageView(onPageContext: { url, title in
                    TrackerService.shared.heatmapCollector.setCurrentPage(url: url, title: title)
                })
                .heatmapGesture()
            }
            .tabItem {
                Label(MainTab.explore.rawValue, systemImage: MainTab.explore.icon)
            }
            .tag(MainTab.explore)

            NavigationStack {
                ConfigSettingsView()
            }
            .tabItem {
                Label(MainTab.settings.rawValue, systemImage: MainTab.settings.icon)
            }
            .tag(MainTab.settings)
        }
        .onChange(of: selectedTab) { _, newTab in
            TrackerService.shared.heatmapCollector.setCurrentPage(
                url: newTab.pageUrl,
                title: newTab.pageTitle
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                TrackerService.shared.churnPointHandler.sendChurnIfNeeded()
            }
        }
        .onAppear {
            TrackerService.shared.heatmapCollector.setCurrentPage(
                url: selectedTab.pageUrl,
                title: selectedTab.pageTitle
            )
        }
    }
}

// MARK: - Heatmap gesture (matches Android pointerInteropFilter: click on down, throttled move)

private struct HeatmapGestureModifier: ViewModifier {
    @State private var isFirstDragValue = true

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = Int(value.location.x)
                        let y = Int(value.location.y)
                        let coord = TrackerService.shared.heatmapCollector
                        if isFirstDragValue {
                            coord.onDragStarted(x: x, y: y)
                            isFirstDragValue = false
                        } else {
                            coord.onDragChanged(x: x, y: y)
                        }
                    }
                    .onEnded { _ in
                        isFirstDragValue = true
                    }
            )
    }
}

extension View {
    fileprivate func heatmapGesture() -> some View {
        modifier(HeatmapGestureModifier())
    }
}

#Preview {
    ContentView()
}
