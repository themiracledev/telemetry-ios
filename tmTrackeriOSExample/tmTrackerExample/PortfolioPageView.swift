//
//  PortfolioPageView.swift
//  tmTrackerExample
//
//  Created by Alban Elshani on 12.2.26.
//

import SwiftUI

struct PortfolioPageView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack {
                Spacer()

                Button(action: {
                    TrackerService.shared.trackClick(
                        elementId: "portfolio-track-button",
                        tagName: "Button",
                        classes: "portfolio-track-button",
                        text: "Portfolio Action",
                        pageUrl: "ios://portfolio",
                        pageTitle: "Portfolio"
                    )
                }) {
                    Text("Portfolio Action")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Portfolio")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        PortfolioPageView()
    }
}
