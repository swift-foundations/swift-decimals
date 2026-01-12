// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-decimals",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(name: "Decimals", targets: ["Decimals"])
    ],
    dependencies: [
        .package(url: "https://github.com/swift-standards/swift-ieee-754.git", from: "0.0.1"),
        .package(url: "https://github.com/swift-primitives/swift-decimal-primitives.git", from: "0.0.1"),
    ],
    targets: [
        .target(
            name: "Decimals",
            dependencies: [
                .product(name: "IEEE 754", package: "swift-ieee-754"),
                .product(name: "Decimal Primitives", package: "swift-decimal-primitives"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        ),
        .testTarget(
            name: "Decimals Tests",
            dependencies: [
                "Decimals",
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
