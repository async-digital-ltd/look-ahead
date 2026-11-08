// swift-tools-version: 6.2
// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "look-ahead",
    // Every platform the consuming apps target. Nothing in the library is
    // platform-specific: a source that uses Background Assets (absent from the
    // watchOS SDK) belongs in the app, not here.
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26),
        .watchOS(.v26)
    ],
    products: [
        .library(
            name: "LookAhead",
            targets: ["LookAhead"]
        )
    ],
    // No dependencies, so an app that adds this package takes no third-party
    // code with it. SwiftLint runs from this checkout (`swiftlint` here,
    // which reads .swiftlint.yml), not as a build plugin, because a
    // consuming app would otherwise resolve and run the plugin too.
    targets: [
        .target(
            name: "LookAhead"
        ),
        .testTarget(
            name: "LookAheadTests",
            dependencies: ["LookAhead"]
        )
    ]
)
