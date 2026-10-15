// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StillpointFeatures",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "StillpointFeatures", targets: ["StillpointFeatures"]),
    ],
    dependencies: [
        .package(path: "../StillpointModel"),
        .package(path: "../StillpointUI"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.0"),
    ],
    targets: [
        .target(
            name: "StillpointFeatures",
            dependencies: [
                .product(name: "StillpointModel", package: "StillpointModel"),
                .product(name: "StillpointUI", package: "StillpointUI"),
            ]
        ),
        .testTarget(
            name: "StillpointFeaturesTests",
            dependencies: [
                "StillpointFeatures",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"]
        ),
    ]
)
