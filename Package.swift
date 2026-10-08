// swift-tools-version:6.2
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors
import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "AxolotlCommander",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "AxolotlCommander", targets: ["AxolotlCommander"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.0"),
    ],
    targets: [
        .systemLibrary(name: "CArchive", path: "Sources/CArchive"),
        .systemLibrary(name: "CCurl", path: "Sources/CCurl"),
        .target(
            name: "CommanderCore",
            dependencies: ["CArchive", "CCurl", .product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: strict
        ),
        .executableTarget(
            name: "AxolotlCommander",
            dependencies: ["CommanderCore"],
            swiftSettings: strict + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "CommanderCoreTests",
            dependencies: ["CommanderCore"],
            swiftSettings: strict
        ),
    ]
)
