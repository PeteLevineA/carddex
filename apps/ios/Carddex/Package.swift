// swift-tools-version: 6.0
// Package.swift for the Carddex iOS app modules.
//
// The app target itself is materialised by Xcode (project.yml -> xcodegen)
// because SwiftPM cannot yet build SwiftUI app targets directly. All shared
// logic lives in libraries here so each module can be unit-tested in isolation.

import PackageDescription

let package = Package(
    name: "Carddex",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "CarddexCore",     targets: ["CarddexCore"]),
        .library(name: "CarddexCatalog",  targets: ["CarddexCatalog"]),
        .library(name: "CarddexScanner",  targets: ["CarddexScanner"]),
        .library(name: "CarddexHolofoil", targets: ["CarddexHolofoil"]),
        .library(name: "CarddexUI",       targets: ["CarddexUI"]),
    ],
    targets: [
        .target(
            name: "CarddexCore",
            path: "Sources/CarddexCore"
        ),
        .target(
            name: "CarddexCatalog",
            dependencies: ["CarddexCore"],
            path: "Sources/CarddexCatalog",
            resources: [
                // Ship the bundled holofoil catalog with the app so first-run
                // works fully offline. The full TCG catalog is loaded out of
                // the documents directory instead (downloaded on first launch).
                .process("Bundled"),
            ]
        ),
        .target(
            name: "CarddexScanner",
            dependencies: ["CarddexCore", "CarddexCatalog"],
            path: "Sources/CarddexScanner"
        ),
        .target(
            name: "CarddexHolofoil",
            dependencies: ["CarddexCore", "CarddexCatalog"],
            path: "Sources/CarddexHolofoil",
            resources: [
                .process("Shaders"),
            ]
        ),
        .target(
            name: "CarddexUI",
            dependencies: ["CarddexCore", "CarddexCatalog", "CarddexScanner", "CarddexHolofoil"],
            path: "Sources/CarddexUI"
        ),

        // MARK: - Tests
        .testTarget(
            name: "CarddexCoreTests",
            dependencies: ["CarddexCore"],
            path: "Tests/CarddexCoreTests"
        ),
        .testTarget(
            name: "CarddexCatalogTests",
            dependencies: ["CarddexCatalog"],
            path: "Tests/CarddexCatalogTests"
        ),
        .testTarget(
            name: "CarddexScannerTests",
            dependencies: ["CarddexScanner"],
            path: "Tests/CarddexScannerTests"
        ),
    ]
)
