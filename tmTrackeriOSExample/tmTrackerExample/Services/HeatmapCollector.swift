//
//  HeatmapCollector.swift
//  tmTrackerExample
//
//  Collects heatmap events (click + throttled move), batches and flushes every 3s.
//  Matches tm_tracker_android heatmap behaviour: 120ms move throttle, periodic flush.
//

import Foundation
import UIKit

/// Thread-safe heatmap queue and flush. Use from main thread for flush/API calls.
final class HeatmapCollector {

    static let flushIntervalSeconds: TimeInterval = 3.0
    static let moveThrottleMs: Int64 = 120

    private let queueLock = NSLock()
    private var _heatmapQueue: [TrackerService.HeatmapPoint] = []
    private var _lastMoveAtMs: Int64 = 0
    private var _currentPageUrl: String = "ios://"
    private var _currentPageTitle: String = ""
    private var flushTimer: Timer?

    var currentPageUrl: String {
        queueLock.lock()
        defer { queueLock.unlock() }
        return _currentPageUrl
    }

    var currentPageTitle: String {
        queueLock.lock()
        defer { queueLock.unlock() }
        return _currentPageTitle
    }

    /// Call when the user navigates so heatmap events use the right page context.
    func setCurrentPage(url: String, title: String) {
        queueLock.lock()
        _currentPageUrl = url
        _currentPageTitle = title
        queueLock.unlock()
    }

    /// Record a tap (touch down) as a "click" heatmap point.
    func addClick(x: Int, y: Int) {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let point = TrackerService.HeatmapPoint(type: "click", x: x, y: y, ts: ts)
        queueLock.lock()
        _heatmapQueue.append(point)
        queueLock.unlock()
    }

    /// Record a move; throttled to once per moveThrottleMs (120ms like Android).
    func addMove(x: Int, y: Int) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        queueLock.lock()
        if nowMs - _lastMoveAtMs < Self.moveThrottleMs {
            queueLock.unlock()
            return
        }
        _lastMoveAtMs = nowMs
        let point = TrackerService.HeatmapPoint(type: "move", x: x, y: y, ts: nowMs)
        _heatmapQueue.append(point)
        queueLock.unlock()
    }

    /// Call when drag gesture starts (first value) to record click at that location.
    func onDragStarted(x: Int, y: Int) {
        addClick(x: x, y: y)
    }

    /// Call on each drag change; throttles move events.
    func onDragChanged(x: Int, y: Int) {
        addMove(x: x, y: y)
    }

    /// Flush current heatmap queue to the API and clear the queue. Uses current page url/title.
    /// Call from main thread for correct ordering when used before churn.
    func flushHeatmap() {
        queueLock.lock()
        let snapshot = _heatmapQueue
        _heatmapQueue.removeAll()
        let url = _currentPageUrl
        let title = _currentPageTitle
        queueLock.unlock()
        if snapshot.isEmpty { return }
        TrackerService.shared.trackHeatmapSnapshot(pageUrl: url, pageTitle: title, heatmap: snapshot)
    }

    /// Start the periodic 3s flush timer. Safe to call multiple times.
    func startPeriodicFlush() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.flushTimer != nil { return }
            self.flushTimer = Timer.scheduledTimer(withTimeInterval: Self.flushIntervalSeconds, repeats: true) { [weak self] _ in
                self?.flushHeatmap()
            }
            self.flushTimer?.tolerance = 0.3
            RunLoop.main.add(self.flushTimer!, forMode: .common)
        }
    }

    /// Stop the periodic flush timer and optionally flush remaining heatmap.
    func stopPeriodicFlush(flushNow: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.flushTimer?.invalidate()
            self.flushTimer = nil
            if flushNow { self.flushHeatmap() }
        }
    }
}
