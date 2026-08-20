// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeTokenBarShared",
    platforms: [.macOS(.v14), .iOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "PokeTokenBarShared", targets: ["PokeTokenBarShared"]),
    ],
    targets: [
        .target(
            name: "PokeTokenBarShared"
        ),
        .testTarget(
            name: "PokeTokenBarSharedTests",
            dependencies: ["PokeTokenBarShared"]
        ),
    ]
)
