//
//  ExploreViewModel.swift
//  tmTrackerExample
//
//  Created by Alban Elshani on 12.2.26.
//

import Foundation
import SwiftUI
import Combine

final class ExploreViewModel: ObservableObject {
    @Published var benefits: [BenefitItem] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    private let repository = BenefitsRepository()
    
    init() {
        Task { @MainActor in
            await loadBenefits()
        }
    }
    
    @MainActor
    func loadBenefits() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let items = try await repository.fetchBenefits()
            self.benefits = items
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to load benefits, contact theMiracle for more info."
            self.isLoading = false
            #if DEBUG
            print("[ExploreViewModel] Failed to load benefits: \(error)")
            #endif
        }
    }
    
    @MainActor
    func refresh() async {
        await loadBenefits()
    }
}
