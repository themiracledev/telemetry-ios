//
//  SwapPageView.swift
//  tmTrackerExample
//
//  Created by Alban Elshani on 12.2.26.
//

import SwiftUI

struct SwapPageView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)

                Text("Swap")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Exchange tokens here")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Swap")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        SwapPageView()
    }
}
