// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StillpointModel",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "StillpointModel", targets: ["StillpointModel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.0"),
    ],
    targets: [
        .target(
            name: "StillpointModel",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "StillpointModelTests",
            dependencies: ["StillpointModel"]
        ),
    ]
)
