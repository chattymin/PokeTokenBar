// swift-tools-version: 6.0
import PackageDescription

// One target, with platform-specific sources and dependencies attached conditionally.
// Splitting Core into its own library target would mean opening ~9,500 lines of internal
// declarations to public purely so the UI can reach them, and would break
// `@testable import PokeTokenBar` in all 33 test files. Wrapping whole files instead — the macOS
// UI in `#if os(macOS)`, the Linux frontend in `#if os(Linux)` — buys the same isolation.
// It also leaves test-gate.sh's coverage paths and build-app.sh's product path valid as they are.
let package = Package(
    name: "PokeTokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Linux-only C system libraries — the dependency conditions keep them out of macOS builds.
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            pkgConfig: "sqlite3",
            providers: [.apt(["libsqlite3-dev"]), .yum(["sqlite-devel"])]
        ),
        .systemLibrary(
            name: "CZlib",
            path: "Sources/CZlib",
            pkgConfig: "zlib",
            providers: [.apt(["zlib1g-dev"]), .yum(["zlib-devel"])]
        ),
        .systemLibrary(
            name: "CGtk",
            path: "Sources/CGtk",
            pkgConfig: "appindicator3-0.1",
            providers: [.apt(["libgtk-3-dev", "libayatana-appindicator3-dev"])]
        ),
        .systemLibrary(
            name: "CNotify",
            path: "Sources/CNotify",
            pkgConfig: "libnotify",
            providers: [.apt(["libnotify-dev"])]
        ),
        .executableTarget(
            name: "PokeTokenBar",
            dependencies: [
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
                .target(name: "CZlib", condition: .when(platforms: [.linux])),
                .target(name: "CGtk", condition: .when(platforms: [.linux])),
                .target(name: "CNotify", condition: .when(platforms: [.linux])),
            ],
            path: "Sources/PokeTokenBar",
            // On Linux, linking is handled by `link "sqlite3"` in the CSQLite module map.
            linkerSettings: [.linkedLibrary("sqlite3", .when(platforms: [.macOS]))]
        ),
        .testTarget(
            name: "PokeTokenBarTests",
            dependencies: [
                "PokeTokenBar",
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
            ],
            path: "Tests/PokeTokenBarTests",
            resources: [
                .copy("Fixtures/CodexFork"),
                .copy("Fixtures/CodexSubagent"),
            ]
        ),
    ]
)
