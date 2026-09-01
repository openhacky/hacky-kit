// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HackyKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .tvOS(.v17),
    ],
    products: [
        .library(name: "HackyKit", targets: ["HackyKit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HackyKit",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "HackyKitTests",
            dependencies: ["HackyKit"]
        ),
    ]
)
