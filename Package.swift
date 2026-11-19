// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeTokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PokeTokenBar",
            path: "Sources/PokeTokenBar",
            // Glue for LAN battles; the simulator itself is downloaded at runtime (BattleEngine.swift).
            resources: [.copy("Resources/battle-bridge.js"), .copy("Resources/battle-text-ru.json")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "PokeTokenBarTests",
            dependencies: ["PokeTokenBar"],
            path: "Tests/PokeTokenBarTests",
            resources: [
                .copy("Fixtures/CodexFork"),
                .copy("Fixtures/CodexSubagent"),
            ]
        ),
    ]
)
