// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeDexBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PokeDexBar",
            path: "Sources/PokeDexBar",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "PokeDexBarTests",
            dependencies: ["PokeDexBar"],
            path: "Tests/PokeDexBarTests",
            resources: [.copy("Fixtures/CodexFork")]
        ),
    ]
)
