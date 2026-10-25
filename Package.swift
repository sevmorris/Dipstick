// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Dipstick",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "Dipstick",
            path: "Sources/Dipstick"
        ),
        .testTarget(
            name: "DipstickTests",
            dependencies: ["Dipstick"],
            path: "Tests/DipstickTests",
            // Real output of mrk's --check modes; Fixtures/README.md says whence.
            resources: [.copy("Fixtures")],
            // Define TESTING so DipstickApp.swift can suppress @main in test builds,
            // preventing a conflict with the XCTest runner's own entry point.
            swiftSettings: [.define("TESTING")]
        ),
    ]
)
