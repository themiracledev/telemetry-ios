# Getting Started — TheMiracleTracking iOS SDK

This guide covers local development setup and how to configure and use the tracking SDK for **pageview**, **time spent**, **click**, **heatmap** and **churnpoint** events.

**For a full working reference, see the example app in this repo:** the `app` module demonstrates integration with Jetpack Compose, including pageview/time spent on benefit detail screens, click tracking, heatmap collection, and churnpoint on lifecycle events.

**Note:** ***All environment variables must be provided by theMiracle team. Do not hardcode these values in your source code.***

---

## Local development

### Requirements

- **iOS 13+**
- **Xcode** with **Swift 5.9+**

### Add the package in Xcode

1. **File → Add Package Dependencies…**
2. Choose **Add Local…** and select the root of the repo and pick that package.
3. Add the **TheMiracleTracking** (or **theMiracleTrackingSDK**) library to your app target.
4. **Import in Swift:**

```swift
import theMiracleTrackingSDK
```

---

## Configuration

You need a few values before creating the tracker. Set environment variables in Xcode: **Product → Scheme → Arguments → Environment Variables** section. The example app reads them from **UserDefaults** → **environment variables** → **Info.plist** (no secrets in code).

### Required values

| Key | Description |
|-----|-------------|
| `ANALYTICS_BASE_URL`    | Analytics API base URL (e.g. `https://api.example.com`) — **required**, no default |
| `ANALYTICS_SDK_ID`      | SDK identifier (must exist in backend) — **required**, no default |
| `ANALYTICS_DISTRIBUTOR` | Distribution channel string — **required**, no default |


### Benefits API Configuration

To fetch benefits data, you also need:

| Key | Description |
|-----|-------------|
| `BENEFITS_API_BASE_URL` | Benefits API base URL (e.g. `https://api.themiracle.io`) — optional, defaults to production if not set |
| `BENEFITS_API_KEY`      | API key for authenticating benefits API requests — **required**, no default |

**Example:** Fetch benefits using these environment variables:

```swift
let baseUrl = AppConfig.string(key: "BENEFITS_API_BASE_URL", default: "https://api.themiracle.io")
let apiKey = AppConfig.requiredString(key: "BENEFITS_API_KEY")

var request = URLRequest(url: URL(string: "\(baseUrl)/api/v1/benefits")!)
request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
// ... make request
```

### SDK config and tracker

Build `SdkConfig` and create a single `Tracker` instance (e.g. in a shared service):

```swift
let apiEndpoints = ApiEndpoints(
    trackBenefitProvider: "/api/v1/bp-page-events/add",
    trackDistributionChannel: "/api/v1/dist-sdk-events/add"
)

let config = SdkConfig(
    apiBaseUrl: "https://your-api.com",
    apiEndpoints: apiEndpoints,
    trackingPlatformType: "distribution-channel",
    distributionChannel: "your-distributor",
    sdkId: "your-sdk-id",
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

let tracker = Tracker(config: config)
```

Use one shared `Tracker` (e.g. `TrackerService.shared.tracker`) for the app.

---

## Implementing tracking events

The SDK provides a **Tracker** with `track(event:)` and `flush()`. Your app sends events to your analytics API (e.g. `/api/v1/dist-sdk-events/add`) with the payload shape your backend expects. The snippets below focus on **what** to send and **when** from the tracking SDK’s perspective.

---

### Pageview (and time spent)

Send a **pageview** when a screen or “page” is shown (e.g. benefit detail, tab). **Refer to the example app** for the full payload shape.

- **When:** On view appear / navigation to the screen.
- **Payload:** Include `eventType: "pageview"`, plus `url`, `title`, `referrer`, session and page metadata.

**Example (conceptual):** when a benefit detail appears, call your API with a payload that includes:

- `eventType`: `"pageview"`
- `url`: e.g. `ios://benefits/benefit-slug`
- `eventData.page`: ***Refer to the example app***
- Session and user metadata (sessionId, timestamps, etc.)

You can derive `pageUrl` / `pageTitle` from your screen (e.g. benefit id/title) and send one pageview per screen view.

**Time spent is a field on the pageview, not a separate event.** When the user stays on the page, you **update** that pageview with the time spent in `eventData.sessionMetadata.totalTimeSpent`. Update when the user leaves the screen, when the app goes to background, or on a periodic timer while the page is visible. Use the same `eventId` (or same resource) as the original pageview so the backend can patch the same record. The SDK does not compute time; you measure elapsed seconds and send the updated pageview payload.

---

### Click

Send when the user taps an element you care about (e.g. CTA, claim button).

- **When:** In the button’s or view’s action handler.
- **SDK:** Use `tracker.track(event:)` with `name: "click"` and properties (tagName, id, text, pageUrl, pageTitle, etc.), then `tracker.flush()` so the SDK side is up to date. Also send the same click to your analytics API so it is stored.

**Example:**

```swift
let event = TrackEvent(
    name: "click",
    properties: [
        TrackProperty(key: "tagName", value: .string(value: "Button")),
        TrackProperty(key: "id", value: .string(value: "benefit-claim-button")),
        TrackProperty(key: "text", value: .string(value: "Claim")),
        TrackProperty(key: "pageUrl", value: .string(value: pageUrl)),
        TrackProperty(key: "pageTitle", value: .string(value: pageTitle)),
        // optional: classes, boundingRect, dataAttributes
    ],
    timestampMs: Int64(Date().timeIntervalSince1970 * 1000)
)
try tracker.track(event: event)
try tracker.flush()
```

Then POST the same click to your analytics endpoint (e.g. `eventType: "click"`, plus element and page info).

---

### Heatmap

Heatmap = batched pointer data (taps and/or moves) per page. The SDK does not send heatmap by itself; you collect coordinates and send them in your own payloads.

- **Collect:** On touch down → record one “click” point; on drag → record “move” points (throttled, e.g. every 120 ms).
- **Send:** Periodically (e.g. every 5 s) or on navigation/background, send a batch with `eventType: "heatmap"` and an array of `{ type, x, y, ts }` for the current page.
- **Page context:** Set “current page” (url/title) when the user changes screen so each batch is tagged with the right page.

**Example (conceptual):**

- **Set page when tab/screen changes:**  
  `heatmapCollector.setCurrentPage(url: "ios://explore", title: "Explore")`
- **On touch down:**  
  `heatmapCollector.addClick(x: x, y: y)` or `onDragStarted(x:y:)`
- **On drag (throttled):**  
  `heatmapCollector.onDragChanged(x: x, y: y)`
- **Flush:**  
  `heatmapCollector.flushHeatmap()` → your code builds the payload and POSTs with `eventType: "heatmap"` and the batch of points.

So: **heatmap = your collector + your API payload**; the “tracking SDK” part is that you use the same session/context as other events and send in the same format as the rest of your analytics.

---

### Churnpoint

Churnpoint = “user left this page/session” (e.g. app backgrounded or navigated away). Send once per leave, with debounce (e.g. 1 s) so you don’t send repeatedly.

- **When:** On scene phase `.background` / `.inactive`, or when the user leaves the current screen.
- **Before sending:** Flush the heatmap for the current page so the last interaction is included, then send one event with `eventType: "churnpoint"` and current page url/title and session metadata.

**Example (conceptual):**

```swift
// On app background or tab/screen leave:
heatmapCollector.flushHeatmap()
trackChurnPoint(pageUrl: currentPageUrl, pageTitle: currentPageTitle)
```

Your `trackChurnPoint` builds the payload (same session/user/page shape as other events) with `eventType: "churnpoint"` and POSTs to theMiracle analytics API.

---

## Summary

| Event       | When to send | SDK usage |
|------------|--------------|-----------|
| **Pageview**   | Screen appear; **time spent** = update same pageview on leave/periodic | Build payload with `eventType: "pageview"`, POST; then update that pageview with time-spent field (same `eventId`). |
| **Click**      | Tap handler   | `tracker.track(event:)` with `name: "click"` + `flush()`, and POST same click to API. |
| **Heatmap**    | Batched taps/moves | Collector (addClick, onDrag*, flushHeatmap) → build payload `eventType: "heatmap"`, POST. |
| **Churnpoint** | Background / leave | Flush heatmap, then build payload `eventType: "churnpoint"`, POST. |

All events are sent to theMiracle analytics backend (e.g. `/api/v1/dist-sdk-events/add`); the SDK’s role is configuration, `Tracker` for clicks, and optional batching/flush behaviour. Session id, sequence numbers, and payload shape are defined by your app and backend; keep them consistent across pageview (and its time-spent updates), click, heatmap, and churnpoint.
