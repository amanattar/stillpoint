// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StillpointUI",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "StillpointUI", targets: ["StillpointUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.0"),
    ],
    targets: [
        .target(name: "StillpointUI"),
        .testTarget(
            name: "StillpointUITests",
            dependencies: [
                "StillpointUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"]
        ),
    ]
)
