// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeTokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PokeTokenBar",
            dependencies: [
                // Windows Swift ships no system `SQLite3` module, so on Windows we build the
                // vendored SQLite amalgamation (Sources/CSQLite) instead. macOS keeps its system
                // `SQLite3`. Either way the OpenCode/Hermes readers get the same sqlite3_* C API.
                .target(name: "CSQLite", condition: .when(platforms: [.windows])),
            ],
            path: "Sources/PokeTokenBar",
            linkerSettings: [
                // macOS links its system libsqlite3; Windows gets sqlite from the CSQLite target above.
                .linkedLibrary("sqlite3", .when(platforms: [.macOS])),
                // GUI subsystem so the tray app spawns no console window (no flash). Keep the
                // standard C entry (mainCRTStartup) since Swift emits `main`, not WinMain.
                // CLI modes re-attach a console at runtime (see WindowsMain.ensureConsole()).
                .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"],
                             .when(platforms: [.windows])),
            ]
        ),
        // Vendored public-domain SQLite amalgamation, compiled only where it's actually depended on
        // (Windows). A plain C target: `include/` holds sqlite3.h + a module map exposing `CSQLite`.
        .target(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .testTarget(
            name: "PokeTokenBarTests",
            dependencies: [
                "PokeTokenBar",
                .target(name: "CSQLite", condition: .when(platforms: [.windows])),
            ],
            path: "Tests/PokeTokenBarTests"
        ),
    ]
)
