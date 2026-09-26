// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCFlyCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CCFlyCore",
            targets: ["CCFlyCore"]
        ),
    ],
    targets: [
        .target(
            name: "CCFlyCore",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CCFlyCoreTests",
            dependencies: ["CCFlyCore"]
        ),
    ]
)
