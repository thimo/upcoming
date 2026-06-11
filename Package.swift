// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Upcoming",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "upcoming", targets: ["Upcoming"]),
        .executable(name: "UpcomingTests", targets: ["UpcomingTests"]),
    ],
    targets: [
        // Models, grouping logic, video-call detection, EventKit service.
        // Everything testable lives here.
        .target(
            name: "UpcomingCore",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        // Thin AppKit + SwiftUI shell.
        .executableTarget(
            name: "Upcoming",
            dependencies: ["UpcomingCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        // Plain executable test runner. XCTest and swift-testing are both
        // unavailable on a Command Line Tools-only toolchain (same setup
        // as Uncommitted).
        .executableTarget(
            name: "UpcomingTests",
            dependencies: ["UpcomingCore"],
            path: "Tests/UpcomingTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
