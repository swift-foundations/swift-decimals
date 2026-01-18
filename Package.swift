// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-decimals",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "Decimals", targets: ["Decimals"])
    ],
    dependencies: [
        .package(path: "../../swift-standards/swift-ieee-754"),
        .package(path: "../../swift-primitives/swift-decimal-primitives")
    ],
    targets: [
        .target(
            name: "Decimals",
            dependencies: [
                .product(name: "IEEE 754", package: "swift-ieee-754"),
                .product(name: "Decimal Primitives", package: "swift-decimal-primitives")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("MemberImportVisibility")
    ]
        )
    ],
    swiftLanguageModes: [.v6]
)
