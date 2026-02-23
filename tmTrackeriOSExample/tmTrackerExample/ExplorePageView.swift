//
//  ExplorePageView.swift
//  tmTrackerExample
//
//  Created by Alban Elshani on 12.2.26.
//

import SwiftUI

struct ExplorePageView: View {
    @StateObject private var viewModel = ExploreViewModel()
    @State private var selectedBenefit: BenefitItem?
    var onPageContext: ((String, String) -> Void)?

    init(onPageContext: ((String, String) -> Void)? = nil) {
        self.onPageContext = onPageContext
    }

    var body: some View {
        Group {
            if let benefit = selectedBenefit {
                BenefitDetailView(
                    benefit: benefit,
                    onBack: { selectedBenefit = nil }
                )
            } else {
                benefitsList
            }
        }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: selectedBenefit) { _, newBenefit in
            updateHeatmapPageContext(selectedBenefit: newBenefit)
        }
        .onAppear {
            updateHeatmapPageContext(selectedBenefit: selectedBenefit)
        }
    }

    private func updateHeatmapPageContext(selectedBenefit: BenefitItem?) {
        guard let onPageContext = onPageContext else { return }
        if let benefit = selectedBenefit {
            onPageContext(TrackerService.pageUrl(forBenefit: benefit), TrackerService.pageTitle(forBenefit: benefit))
        } else {
            onPageContext("ios://explore", "Explore")
        }
    }
    
    private var benefitsList: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.benefits.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No benefits available yet.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.benefits) { benefit in
                            BenefitListItemView(benefit: benefit)
                                .onTapGesture {
                                    selectedBenefit = benefit
                                }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct BenefitListItemView: View {
    let benefit: BenefitItem
    
    var body: some View {
        HStack(spacing: 12) {
            if !benefit.thumbnail.isEmpty, let url = URL(string: benefit.thumbnail) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(benefit.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if !benefit.labels.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(benefit.labels.prefix(2), id: \.self) { label in
                            Text(label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.2))
                                .foregroundStyle(.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                
                Text(benefit.dateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        ExplorePageView()
    }
}
