//
//  BenefitDetailView.swift
//  tmTrackerExample
//
//  Created by Alban Elshani on 12.2.26.
//

import SwiftUI
import Combine

// Timer manager class to hold timer state and allow access to current start time
class TimespentTimerManager: ObservableObject {
    var timer: Timer?
    var startTime: Date?
    var benefit: BenefitItem
    var timespentEventId: String? // Store eventId for this page view to reuse in periodic updates
    
    // Store eventId per benefit ID to persist across view recreations
    private static var eventIdCache: [Int: String] = [:]
    
    init(benefit: BenefitItem) {
        self.benefit = benefit
        // Try to restore eventId from cache if view was recreated
        if let cachedEventId = Self.eventIdCache[benefit.id] {
            self.timespentEventId = cachedEventId
            #if DEBUG
            print("[TimespentTimerManager] Restored cached eventId: \(cachedEventId) for benefit \(benefit.id)")
            #endif
        }
    }
    
    func updateBenefit(_ benefit: BenefitItem) {
        self.benefit = benefit
        // Restore eventId from cache if available
        if let cachedEventId = Self.eventIdCache[benefit.id], timespentEventId == nil {
            self.timespentEventId = cachedEventId
            #if DEBUG
            print("[TimespentTimerManager] Restored cached eventId: \(cachedEventId) for benefit \(benefit.id)")
            #endif
        }
    }
    
    func setTimespentEventId(_ eventId: String) {
        self.timespentEventId = eventId
        // Cache eventId per benefit ID
        Self.eventIdCache[benefit.id] = eventId
        #if DEBUG
        print("[TimespentTimerManager] Set timespentEventId: \(eventId) for benefit \(benefit.id)")
        #endif
    }
    
    func clearTimespentEventId() {
        #if DEBUG
        print("[TimespentTimerManager] Clearing timespentEventId (was: \(timespentEventId ?? "nil")) for benefit \(benefit.id)")
        #endif
        self.timespentEventId = nil
        // Don't clear cache immediately - keep it for a bit in case view is recreated
        // Cache will be cleared when navigating away
    }
    
    static func clearEventIdCache(for benefitId: Int) {
        eventIdCache.removeValue(forKey: benefitId)
        #if DEBUG
        print("[TimespentTimerManager] Cleared eventId cache for benefit \(benefitId)")
        #endif
    }
    
    func start(startTime: Date) {
        stop()
        self.startTime = startTime

        #if DEBUG
        print("[TimespentTimerManager] Starting timer for benefit \(benefit.id) at \(startTime), eventId: \(timespentEventId ?? "nil")")
        #endif

        guard timespentEventId != nil else {
            #if DEBUG
            print("[TimespentTimerManager] ERROR: Cannot start timer without eventId!")
            #endif
            return
        }

        // Schedule on main run loop so it fires every 5s even during scroll (common mode)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] t in
                guard let self = self, let start = self.startTime else {
                    t.invalidate()
                    return
                }
                let now = Date()
                let elapsed = now.timeIntervalSince(start)
                #if DEBUG
                print("[TimespentTimerManager] Timer fired - elapsed: \(elapsed)s")
                #endif
                guard elapsed >= 5.0 else { return }
                guard let eventId = self.timespentEventId else {
                    t.invalidate()
                    return
                }
                #if DEBUG
                print("[TimespentTimerManager] Sending periodic timespent - \(Int(elapsed))s, eventId: \(eventId)")
                #endif
                TrackerService.shared.trackBenefitTimeSpent(
                    benefit: self.benefit,
                    startTime: start,
                    endTime: now,
                    reason: "periodic",
                    eventId: eventId
                )
            }
            self.timer?.tolerance = 0.5
            if let timer = self.timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    
    func stop() {
        #if DEBUG
        print("[TimespentTimerManager] Stopping timer")
        #endif
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        stop()
    }
}

struct BenefitDetailView: View {
    let benefit: BenefitItem
    let onBack: () -> Void
    
    @State private var viewStartTime: Date?
    @StateObject private var timerManager: TimespentTimerManager
    @Environment(\.scenePhase) private var scenePhase
    
    init(benefit: BenefitItem, onBack: @escaping () -> Void) {
        self.benefit = benefit
        self.onBack = onBack
        _timerManager = StateObject(wrappedValue: TimespentTimerManager(benefit: benefit))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Thumbnail
                if !benefit.thumbnail.isEmpty, let url = URL(string: benefit.thumbnail) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 200)
                }
                
                // Labels row
                HStack {
                    Text("Your Brand")
                        .font(.headline)
                    
                    Spacer()
                    
                    if !benefit.labels.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(benefit.labels.prefix(2), id: \.self) { label in
                                Text(label)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.2))
                                    .foregroundStyle(.primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                
                // Title
                Text(benefit.title)
                    .font(.title)
                    .fontWeight(.bold)
                
                // Date
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ends")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(benefit.dateLabel)
                        .font(.body)
                }
                
                // Description
                Text(benefit.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                
                // Claim button
                Button(action: {
                    TrackerService.shared.trackBenefitClaimClick(benefit: benefit)
                }) {
                    Text("Claim")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    // Send final timespent before navigating back
                    timerManager.stop()
                    if let start = viewStartTime {
                        TrackerService.shared.trackBenefitTimeSpent(
                            benefit: benefit,
                            startTime: start,
                            endTime: Date(),
                            reason: "navigate",
                            eventId: timerManager.timespentEventId
                        )
                        viewStartTime = nil
                    }
                    timerManager.clearTimespentEventId()
                    TimespentTimerManager.clearEventIdCache(for: benefit.id)
                    onBack()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                }
            }
        }
        .onAppear {
            let startTime = Date()
            viewStartTime = startTime
            timerManager.updateBenefit(benefit) // Ensure timer manager has current benefit
            
            // Generate eventId for this page view - will be reused for all periodic updates
            // IMPORTANT: Set eventId BEFORE starting timer so timer closure can access it
            // If eventId already exists (from cache or previous set), reuse it; otherwise generate new one
            let timespentEventId: String
            if let existingEventId = timerManager.timespentEventId {
                timespentEventId = existingEventId
                #if DEBUG
                print("[BenefitDetailView] onAppear - Reusing existing timespentEventId: \(timespentEventId)")
                #endif
            } else {
                timespentEventId = UUID().uuidString
                timerManager.setTimespentEventId(timespentEventId)
                #if DEBUG
                print("[BenefitDetailView] onAppear - Generated NEW timespentEventId: \(timespentEventId) for benefit \(benefit.id)")
                #endif
            }
            
            TrackerService.shared.trackBenefitPageView(benefit: benefit, referrer: "ios://explore")
            timerManager.start(startTime: startTime)
            
            #if DEBUG
            print("[BenefitDetailView] onAppear - Timer started, stored eventId: \(timerManager.timespentEventId ?? "nil")")
            #endif
        }
        .onDisappear {
            timerManager.stop()
            if let start = viewStartTime {
                TrackerService.shared.trackBenefitTimeSpent(
                    benefit: benefit,
                    startTime: start,
                    endTime: Date(),
                    reason: "exit",
                    eventId: timerManager.timespentEventId
                )
                viewStartTime = nil
            }
            timerManager.clearTimespentEventId()
            TimespentTimerManager.clearEventIdCache(for: benefit.id)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard let start = viewStartTime else { return }
            
            if newPhase == .background || newPhase == .inactive {
                timerManager.stop()
                TrackerService.shared.trackBenefitTimeSpent(
                    benefit: benefit,
                    startTime: start,
                    endTime: Date(),
                    reason: "background",
                    eventId: timerManager.timespentEventId
                )
                viewStartTime = nil
            } else if newPhase == .active && oldPhase != .active {
                let newStart = Date()
                viewStartTime = newStart
                // Generate new eventId when returning to foreground (new session)
                let timespentEventId = UUID().uuidString
                timerManager.setTimespentEventId(timespentEventId)
                timerManager.start(startTime: newStart)
            }
        }
    }
}

#Preview {
    NavigationStack {
        BenefitDetailView(
            benefit: BenefitItem(
                id: 1,
                thumbnail: "",
                title: "Sample Benefit",
                description: "This is a sample benefit description.",
                labels: ["Type", "Company"],
                dateLabel: "1st January 2026"
            ),
            onBack: {}
        )
    }
}
