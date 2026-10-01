// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CleanCore",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "CleanCore", targets: ["CleanCore"]),
    ],
    targets: [
        .target(
            name: "CleanCore",
            path: "Sources/CleanCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CleanCoreTests",
            dependencies: ["CleanCore"],
            path: "Tests/CleanCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
