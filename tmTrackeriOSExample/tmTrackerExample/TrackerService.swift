//
//  TrackerService.swift
//  tmTrackerExample
//
//  Created by Alban Elshani on 12.2.26.
//

import Foundation
import UIKit
import theMiracleTrackingSDK

/// Shared service to send events to the analytics API.
/// Uses the same payload shape as Android's sendClickEventToApi so the backend persists to DB.
final class TrackerService {

    static let shared = TrackerService()

    private let tracker: Tracker

    /// Analytics API base URL. Set via Settings tab (UserDefaults), env ANALYTICS_BASE_URL, or Info.plist.
    private static var apiBaseUrl: String {
        AppConfig.requiredString(key: "ANALYTICS_BASE_URL")
    }
    private static let trackEndpoint = "/api/v1/dist-sdk-events/add"
    /// SDK ID (must exist in backend). REQUIRED: Set via Settings tab, env ANALYTICS_SDK_ID, or Info.plist.
    /// No default - must be configured to avoid exposing secrets in code.
    private static var sdkId: String {
        AppConfig.requiredString(key: "ANALYTICS_SDK_ID")
    }
    /// Distribution channel. Set via Settings tab, env ANALYTICS_DISTRIBUTOR, or Info.plist.
    private static var distributor: String {
        AppConfig.requiredString(key: "ANALYTICS_DISTRIBUTOR")
    }

    private let sequenceKey = "themiracle_tracker_sequence"
    private let sessionIdKey = "themiracle_tracker_session"
    private let sessionFirstTouchKey = "themiracle_tracker_session_first_touch"
    private let sessionLastTouchKey = "themiracle_tracker_session_last_touch"
    private let sessionTotalVisitsKey = "themiracle_tracker_session_total_visits"

    /// Heatmap: queue, throttle, periodic flush. Churn: lifecycle + debounce (flushes heatmap then sends).
    private(set) lazy var heatmapCollector: HeatmapCollector = {
        let c = HeatmapCollector()
        c.startPeriodicFlush()
        return c
    }()

    private(set) lazy var churnPointHandler: ChurnPointHandler = {
        ChurnPointHandler(heatmapCollector: heatmapCollector)
    }()

    private init() {
        let config = Self.buildSdkConfig()
        self.tracker = Tracker(config: config)
    }

    private static func buildSdkConfig() -> SdkConfig {
        let apiEndpoints = ApiEndpoints(
            trackBenefitProvider: "/api/v1/bp-page-events/add",
            trackDistributionChannel: "/api/v1/dist-sdk-events/add"
        )
        return SdkConfig(
            apiBaseUrl: Self.apiBaseUrl,
            apiEndpoints: apiEndpoints,
            trackingPlatformType: "distribution-channel",
            distributionChannel: distributor,
            sdkId: sdkId,
            customSelectors: [],
            debounceDelay: 300,
            debug: true,
            trackClicks: true,
            trackPageviews: true,
            trackPageClose: true,
            trackTimeSpent: true,
            trackHeatmap: true,
            trackChurnPoint: true
        )
    }

    // MARK: - Heatmap & Churn (payload shape matches Android TrackingAnalytics)

    struct HeatmapPoint {
        let type: String  // "click" | "move"
        let x: Int
        let y: Int
        let ts: Int64
    }

    /// Sends a batched heatmap snapshot to the API (eventType: "heatmap").
    func trackHeatmapSnapshot(pageUrl: String, pageTitle: String, heatmap: [HeatmapPoint]) {
        guard !heatmap.isEmpty else { return }
        let nowIso = formatISO8601Instant(date: Date())
        let sessionMetadata = getAndUpdateSessionMetadata(nowIso: nowIso)
        let sessionId = getOrCreateSessionId()
        let heatmapArray = heatmap.map { p -> [String: Any] in
            ["type": p.type, "x": p.x, "y": p.y, "ts": p.ts]
        }
        let eventData: [String: Any] = [
            "sessionMetadata": sessionMetadata,
            "performanceTiming": buildPerformanceTiming(),
            "networkState": buildNetworkState(),
            "page": buildPageInfo(url: pageUrl, title: pageTitle, referrer: ""),
            "user": buildUserInfo(nowIso: nowIso, sessionId: sessionId),
            "heatmap": heatmapArray,
        ]
        let payload: [String: Any] = [
            "distributor": Self.distributor,
            "url": pageUrl,
            "eventId": UUID().uuidString,
            "sequenceNumber": getNextSequenceNumber(),
            "eventTimestamp": nowIso,
            "eventType": "heatmap",
            "eventData": eventData,
        ]
        sendAnalyticsEvent(payload: payload, eventType: "heatmap")
    }

    /// Sends a churn point event (eventType: "churnpoint") when user leaves or app backgrounds.
    func trackChurnPoint(pageUrl: String, pageTitle: String) {
        let nowIso = formatISO8601Instant(date: Date())
        let sessionMetadata = getAndUpdateSessionMetadata(nowIso: nowIso)
        let sessionId = getOrCreateSessionId()
        let eventData: [String: Any] = [
            "sessionMetadata": sessionMetadata,
            "performanceTiming": buildPerformanceTiming(),
            "networkState": buildNetworkState(),
            "page": buildPageInfo(url: pageUrl, title: pageTitle, referrer: ""),
            "user": buildUserInfo(nowIso: nowIso, sessionId: sessionId),
        ]
        let payload: [String: Any] = [
            "distributor": Self.distributor,
            "url": pageUrl,
            "eventId": UUID().uuidString,
            "sequenceNumber": getNextSequenceNumber(),
            "eventTimestamp": nowIso,
            "eventType": "churnpoint",
            "eventData": eventData,
        ]
        sendAnalyticsEvent(payload: payload, eventType: "churnpoint")
    }

    /// Exposed for heatmap/churn current-page context (e.g. benefit detail).
    static func pageUrl(forBenefit benefit: BenefitItem) -> String {
        let slug = benefit.title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "ios://benefits/\(slug)"
    }

    static func pageTitle(forBenefit benefit: BenefitItem) -> String {
        "Benefit: \(benefit.title)"
    }

    /// Sends a click event: SDK track+flush and a direct HTTP POST with the payload the API expects (so it is saved to DB).
    func trackClick(
        elementId: String,
        tagName: String = "Button",
        classes: String = "",
        text: String,
        pageUrl: String,
        pageTitle: String,
        boundingRectJson: String = "{}",
        dataAttributesJson: String = "{}"
    ) {
        // 1) SDK path (for consistency with other platforms)
        let event = TrackEvent(
            name: "click",
            properties: [
                TrackProperty(key: "tagName", value: .string(value: tagName)),
                TrackProperty(key: "id", value: .string(value: elementId)),
                TrackProperty(key: "classes", value: .string(value: classes)),
                TrackProperty(key: "text", value: .string(value: text)),
                TrackProperty(key: "boundingRect", value: .string(value: boundingRectJson)),
                TrackProperty(key: "dataAttributes", value: .string(value: dataAttributesJson)),
                TrackProperty(key: "pageUrl", value: .string(value: pageUrl)),
                TrackProperty(key: "pageTitle", value: .string(value: pageTitle)),
            ],
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        do {
            try tracker.track(event: event)
            try tracker.flush()
        } catch {
            #if DEBUG
            print("[TrackerService] SDK track/flush failed: \(error)")
            #endif
        }

        // 2) Direct HTTP POST with payload shape the API expects (same as Android sendClickEventToApi)
        sendClickEventToApi(
            elementId: elementId,
            tagName: tagName,
            classes: classes,
            text: text,
            pageUrl: pageUrl,
            pageTitle: pageTitle,
            boundingRectJson: boundingRectJson,
            dataAttributesJson: dataAttributesJson
        )
    }

    // MARK: - Direct API send (payload matches backend / distribution-sdk-event validator)

    private func getNextSequenceNumber() -> Int {
        let n = (UserDefaults.standard.object(forKey: sequenceKey) as? Int) ?? 0
        let next = n + 1
        UserDefaults.standard.set(next, forKey: sequenceKey)
        return next
    }

    private func getOrCreateSessionId() -> String {
        if let existing = UserDefaults.standard.string(forKey: sessionIdKey), !existing.isEmpty {
            return existing
        }
        let newId = "session_\(String(format: "%09llx", UInt64(Date().timeIntervalSince1970 * 1000)))_\(UInt64(Date().timeIntervalSince1970 * 1000))"
        UserDefaults.standard.set(newId, forKey: sessionIdKey)
        return newId
    }

    private func sendClickEventToApi(
        elementId: String,
        tagName: String,
        classes: String,
        text: String,
        pageUrl: String,
        pageTitle: String,
        boundingRectJson: String,
        dataAttributesJson: String
    ) {
        let nowIso = formatISO8601Instant(date: Date())
        let eventId = UUID().uuidString
        let sequence = getNextSequenceNumber()
        let sessionId = getOrCreateSessionId()

        let pageId: String = {
            let data = pageUrl.data(using: .utf8) ?? Data()
            return data.base64EncodedString().replacingOccurrences(of: "=", with: "")
        }()

        let eventData: [String: Any] = [
            "metadata": [
                "timestamp": nowIso,
                "viewport": "\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))",
                "coordinates": ["x": NSNull(), "y": NSNull()] as [String: Any],
            ],
            "sessionMetadata": [
                "firstTouchAt": nowIso,
                "lastTouchAt": nowIso,
                "totalVisits": 1,
                "totalTimeSpent": NSNull(),
            ],
            "performanceTiming": [
                "domContentLoaded": NSNull(),
                "loadEventEnd": NSNull(),
                "responseStart": NSNull(),
                "firstPaint": NSNull(),
                "firstContentfulPaint": NSNull(),
            ],
            "networkState": [
                "online": true,
                "effectiveType": NSNull(),
                "downlink": NSNull(),
                "rtt": NSNull(),
            ],
            "element": [
                "tagName": tagName,
                "id": elementId,
                "classes": classes,
                "text": text,
                "dataAttributes": (try? JSONSerialization.jsonObject(with: dataAttributesJson.data(using: .utf8) ?? Data())) as? [String: Any] ?? [:],
                "boundingRect": (try? JSONSerialization.jsonObject(with: boundingRectJson.data(using: .utf8) ?? Data())) as? [String: Any] ?? [:],
            ],
            "page": [
                "url": pageUrl,
                "title": pageTitle,
                "referrer": "",
                "pageId": pageId,
                "navigationType": "navigate",
            ],
            "user": [
                "userAgent": "iOS/\(UIDevice.current.systemVersion) (\(UIDevice.current.model))",
                "language": String(Locale.current.identifier),
                "timezone": TimeZone.current.identifier,
                "screenResolution": "\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))",
                "colorDepth": 24,
                "sessionId": sessionId,
                "timestamp": nowIso,
            ],
        ]

        let payload: [String: Any] = [
            "distributor": Self.distributor,
            "url": pageUrl,
            "eventId": eventId,
            "sequenceNumber": sequence,
            "eventTimestamp": nowIso,
            "eventType": "click",
            "eventData": eventData,
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let urlString = "\(Self.apiBaseUrl)\(Self.trackEndpoint)?sdkId=\(Self.sdkId)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.sdkId, forHTTPHeaderField: "X-SDK-ID")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, error in
            #if DEBUG
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let error = error {
                print("[TrackerService] HTTP click failed: \(error)")
            } else {
                print("[TrackerService] Click event HTTP response: \(code)")
            }
            #endif
        }.resume()
    }
    
    // MARK: - Benefit Pageview Tracking
    
    func trackBenefitPageView(benefit: BenefitItem, referrer: String) {
        let nowIso = formatISO8601Instant(date: Date())
        let pageUrl = buildBenefitPageUrl(benefit)
        let pageTitle = buildBenefitPageTitle(benefit)
        
        let sessionMetadata = getAndUpdateSessionMetadata(nowIso: nowIso)
        let sessionId = getOrCreateSessionId()
        
        let eventData: [String: Any] = [
            "sessionMetadata": sessionMetadata,
            "performanceTiming": buildPerformanceTiming(),
            "networkState": buildNetworkState(),
            "page": buildPageInfo(url: pageUrl, title: pageTitle, referrer: referrer),
            "user": buildUserInfo(nowIso: nowIso, sessionId: sessionId),
            "benefit": buildBenefitInfo(benefit: benefit, reason: nil),
        ]
        
        let payload: [String: Any] = [
            "distributor": Self.distributor,
            "url": pageUrl,
            "eventId": UUID().uuidString,
            "sequenceNumber": getNextSequenceNumber(),
            "eventTimestamp": nowIso,
            "eventType": "pageview",
            "eventData": eventData,
        ]
        
        sendAnalyticsEvent(payload: payload, eventType: "pageview")
    }
    
    // MARK: - Benefit Time Spent Tracking
    
    func trackBenefitTimeSpent(benefit: BenefitItem, startTime: Date, endTime: Date, reason: String, eventId: String? = nil) {
        let diffMs = endTime.timeIntervalSince(startTime) * 1000
        guard diffMs > 0 else { return }
        
        // Round down but ensure minimum 1 second
        let totalSeconds = max(Int64(diffMs / 1000), 1)
        
        let startIso = formatISO8601Instant(date: startTime)
        let endIso = formatISO8601Instant(date: endTime)
        let nowIso = endIso
        
        let pageUrl = buildBenefitPageUrl(benefit)
        let pageTitle = buildBenefitPageTitle(benefit)
        let referrer = "ios://explore"
        
        var sessionMetadata = getAndUpdateSessionMetadata(nowIso: nowIso)
        sessionMetadata["totalTimeSpent"] = totalSeconds
        sessionMetadata["firstTouchAt"] = startIso
        sessionMetadata["lastTouchAt"] = endIso
        
        let sessionId = getOrCreateSessionId()
        
        #if DEBUG
        print("[TrackerService] trackBenefitTimeSpent - sessionId: \(sessionId), reason: \(reason), totalSeconds: \(totalSeconds)")
        #endif
        
        let eventData: [String: Any] = [
            "sessionMetadata": sessionMetadata,
            "performanceTiming": buildPerformanceTiming(),
            "networkState": buildNetworkState(),
            "page": buildPageInfo(url: pageUrl, title: pageTitle, referrer: referrer),
            "user": buildUserInfo(nowIso: nowIso, sessionId: sessionId),
            "benefit": buildBenefitInfo(benefit: benefit, reason: reason),
        ]
        
        // Use provided eventId for periodic updates, or generate new one for initial/final events
        // This ensures the same eventId is used for all periodic updates on the same page
        let finalEventId: String
        if let providedEventId = eventId {
            finalEventId = providedEventId
            #if DEBUG
            print("[TrackerService] Using provided eventId: \(providedEventId) for reason: \(reason)")
            #endif
        } else {
            finalEventId = UUID().uuidString
            #if DEBUG
            print("[TrackerService] WARNING: No eventId provided, generating new one: \(finalEventId) for reason: \(reason)")
            #endif
        }
        
        let payload: [String: Any] = [
            "distributor": Self.distributor,
            "url": pageUrl,
            "eventId": finalEventId, // Reuse same eventId for periodic updates on same page
            "sequenceNumber": getNextSequenceNumber(),
            "eventTimestamp": nowIso,
            "eventType": "timespent",
            "eventData": eventData,
        ]
        
        #if DEBUG
        print("[TrackerService] Timespent payload - eventId: \(finalEventId), sessionId: \(sessionId), url: \(pageUrl), totalSeconds: \(totalSeconds), reason: \(reason)")
        #endif
        
        sendAnalyticsEvent(payload: payload, eventType: "timespent")
    }
    
    // MARK: - Benefit Claim Click Tracking
    
    func trackBenefitClaimClick(benefit: BenefitItem) {
        let nowIso = formatISO8601Instant(date: Date())
        let pageUrl = buildBenefitPageUrl(benefit)
        let pageTitle = buildBenefitPageTitle(benefit)
        let referrer = "ios://explore"
        
        let sessionMetadata = getAndUpdateSessionMetadata(nowIso: nowIso)
        let sessionId = getOrCreateSessionId()
        
        let element: [String: Any] = [
            "tagName": "Button",
            "id": "benefit-claim-button",
            "classes": "benefit-claim-button",
            "text": "Claim",
            "dataAttributes": [:] as [String: Any],
            "boundingRect": [:] as [String: Any],
        ]
        
        let eventData: [String: Any] = [
            "metadata": [
                "timestamp": nowIso,
                "viewport": "\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))",
                "coordinates": ["x": NSNull(), "y": NSNull()] as [String: Any],
            ],
            "sessionMetadata": sessionMetadata,
            "performanceTiming": buildPerformanceTiming(),
            "networkState": buildNetworkState(),
            "element": element,
            "page": buildPageInfo(url: pageUrl, title: pageTitle, referrer: referrer),
            "user": buildUserInfo(nowIso: nowIso, sessionId: sessionId),
            "benefit": buildBenefitInfo(benefit: benefit, reason: nil),
        ]
        
        let payload: [String: Any] = [
            "distributor": Self.distributor,
            "url": pageUrl,
            "eventId": UUID().uuidString,
            "sequenceNumber": getNextSequenceNumber(),
            "eventTimestamp": nowIso,
            "eventType": "click",
            "eventData": eventData,
        ]
        
        sendAnalyticsEvent(payload: payload, eventType: "click")
    }
    
    // MARK: - Helper Methods

    private func buildBenefitPageUrl(_ benefit: BenefitItem) -> String {
        Self.pageUrl(forBenefit: benefit)
    }

    private func buildBenefitPageTitle(_ benefit: BenefitItem) -> String {
        Self.pageTitle(forBenefit: benefit)
    }

    private func base64EncodeNoPadding(_ input: String) -> String {
        let data = input.data(using: .utf8) ?? Data()
        return data.base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
    
    private func getAndUpdateSessionMetadata(nowIso: String) -> [String: Any] {
        let firstTouch = UserDefaults.standard.string(forKey: sessionFirstTouchKey) ?? nowIso
        let totalVisits = UserDefaults.standard.integer(forKey: sessionTotalVisitsKey) + 1
        
        UserDefaults.standard.set(firstTouch, forKey: sessionFirstTouchKey)
        UserDefaults.standard.set(nowIso, forKey: sessionLastTouchKey)
        UserDefaults.standard.set(totalVisits, forKey: sessionTotalVisitsKey)
        
        return [
            "firstTouchAt": firstTouch,
            "lastTouchAt": nowIso,
            "totalVisits": totalVisits,
            "totalTimeSpent": NSNull(),
        ]
    }
    
    private func buildPerformanceTiming() -> [String: Any] {
        return [
            "domContentLoaded": NSNull(),
            "loadEventEnd": NSNull(),
            "responseStart": NSNull(),
            "firstPaint": NSNull(),
            "firstContentfulPaint": NSNull(),
        ]
    }
    
    private func buildNetworkState() -> [String: Any] {
        return [
            "online": true,
            "effectiveType": NSNull(),
            "downlink": NSNull(),
            "rtt": NSNull(),
        ]
    }
    
    private func buildPageInfo(url: String, title: String, referrer: String) -> [String: Any] {
        return [
            "url": url,
            "title": title,
            "referrer": referrer,
            "pageId": base64EncodeNoPadding(url),
            "navigationType": "navigate",
        ]
    }
    
    private func buildUserInfo(nowIso: String, sessionId: String) -> [String: Any] {
        return [
            "userAgent": "iOS/\(UIDevice.current.systemVersion) (\(UIDevice.current.model))",
            "language": String(Locale.current.identifier.prefix(2)),
            "timezone": TimeZone.current.identifier,
            "screenResolution": "\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))",
            "colorDepth": 24,
            "sessionId": sessionId,
            "timestamp": nowIso,
        ]
    }
    
    private func buildBenefitInfo(benefit: BenefitItem, reason: String?) -> [String: Any] {
        var info: [String: Any] = [
            "id": benefit.id,
            "title": benefit.title,
            "labels": benefit.labels,
        ]
        if let reason = reason, !reason.isEmpty {
            info["reason"] = reason
        }
        return info
    }
    
    // Format date as ISO 8601 Instant (matching Android's DateTimeFormatter.ISO_INSTANT format)
    // Example: "2026-02-13T10:30:00Z"
    private func formatISO8601Instant(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
        return formatter.string(from: date)
    }
    
    private func sendAnalyticsEvent(payload: [String: Any], eventType: String) {
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            #if DEBUG
            print("[TrackerService] Failed to serialize \(eventType) payload")
            #endif
            return
        }
        
        let urlString = "\(Self.apiBaseUrl)\(Self.trackEndpoint)?sdkId=\(Self.sdkId)"
        guard let url = URL(string: urlString) else {
            #if DEBUG
            print("[TrackerService] Invalid URL for \(eventType): \(urlString)")
            #endif
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.sdkId, forHTTPHeaderField: "X-SDK-ID")
        request.httpBody = body
        request.timeoutInterval = 10.0 // Match Android's 10 second timeout
        
        #if DEBUG
        if let payloadString = String(data: body, encoding: .utf8) {
            print("[TrackerService] Sending \(eventType) event to \(urlString)")
            if eventType == "timespent", let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let eventData = json["eventData"] as? [String: Any],
               let user = eventData["user"] as? [String: Any],
               let sessionId = user["sessionId"] as? String {
                print("[TrackerService] Timespent event - eventId: \(json["eventId"] ?? "nil"), sessionId: \(sessionId)")
            }
            print("[TrackerService] Payload preview: \(String(payloadString.prefix(300)))")
        }
        #endif
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            #if DEBUG
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let error = error {
                print("[TrackerService] HTTP \(eventType) failed: \(error)")
            } else {
                let responsePreview = data.flatMap { String(data: $0, encoding: .utf8)?.prefix(300) } ?? "no body"
                print("[TrackerService] \(eventType.prefix(1).uppercased() + eventType.dropFirst()) event HTTP response: \(code), body: \(responsePreview)")
            }
            #endif
        }.resume()
    }
}
