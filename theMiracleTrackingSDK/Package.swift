// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "theMiracleTrackingSDK",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "theMiracleTrackingSDK",
            targets: ["theMiracleTrackingSDK"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "themiracle_trackingFFI",
            path: "Binaries/themiracle_tracking.xcframework"
        ),
        .target(
            name: "theMiracleTrackingSDK",
            dependencies: ["themiracle_trackingFFI"],
            path: "Sources/TheMiracleTracking"
        ),
        .testTarget(
            name: "theMiracleTrackingSDKTests",
            dependencies: ["theMiracleTrackingSDK"]
        ),
    ]
)
