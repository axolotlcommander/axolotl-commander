// swift-tools-version:6.2
import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "iCommander",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "iCommander", targets: ["iCommander"]),
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
            name: "iCommander",
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
