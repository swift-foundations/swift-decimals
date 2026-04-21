// swift-tools-version: 6.3.1

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
        .package(path: "../../swift-ieee/swift-ieee-754"),
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
        ),
        .testTarget(
            name: "Decimals Tests",
            dependencies: [
                "Decimals",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)


for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
