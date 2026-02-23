//
//  ChurnPointHandler.swift
//  tmTrackerExample
//
//  Sends a churn-point event when the user leaves (e.g. app to background).
//  Matches tm_tracker_android: 1s debounce, and flushes heatmap before sending churn.
//

import Foundation
import UIKit

/// Sends churn point events with debounce. Flushes heatmap first when sending (like Android).
final class ChurnPointHandler {

    static let churnDebounceMs: Int64 = 1000

    private let queueLock = NSLock()
    private var _lastChurnAtMs: Int64 = 0
    private weak var heatmapCollector: HeatmapCollector?

    init(heatmapCollector: HeatmapCollector) {
        self.heatmapCollector = heatmapCollector
    }

    /// If at least churnDebounceMs (1s) since last churn: flush heatmap then send churn point.
    func sendChurnIfNeeded() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        queueLock.lock()
        if nowMs - _lastChurnAtMs < Self.churnDebounceMs {
            queueLock.unlock()
            return
        }
        _lastChurnAtMs = nowMs
        queueLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.heatmapCollector?.flushHeatmap()
            let url = self.heatmapCollector?.currentPageUrl ?? "ios://"
            let title = self.heatmapCollector?.currentPageTitle ?? ""
            TrackerService.shared.trackChurnPoint(pageUrl: url, pageTitle: title)
        }
    }
}
