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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
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
        // Thin AppKit + SwiftUI shell. Depends on Sparkle for auto-updates.
        .executableTarget(
            name: "Upcoming",
            dependencies: [
                "UpcomingCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources"),
            ],
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
