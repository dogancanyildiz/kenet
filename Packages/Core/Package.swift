// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "VaultFormat", targets: ["VaultFormat"]),
        .library(name: "VaultIndex", targets: ["VaultIndex"]),
        .library(name: "VaultStore", targets: ["VaultStore"]),
        .library(name: "EntityRecognition", targets: ["EntityRecognition"]),
        .library(name: "DateParsing", targets: ["DateParsing"]),
        .library(name: "GoalTracking", targets: ["GoalTracking"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "VaultStore", dependencies: ["VaultFormat", "VaultIndex", "GoalTracking"]),
        .testTarget(
            name: "VaultStoreTests",
            dependencies: ["VaultStore", "VaultIndex", "GoalTracking", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "GoalTracking", dependencies: ["VaultFormat"]),
        .testTarget(name: "GoalTrackingTests", dependencies: ["GoalTracking", "VaultFormat"]),
        .target(name: "DateParsing", dependencies: ["VaultFormat"]),
        .testTarget(name: "DateParsingTests", dependencies: ["DateParsing", "VaultFormat"]),
        .target(name: "EntityRecognition", dependencies: ["VaultFormat"]),
        .testTarget(name: "EntityRecognitionTests", dependencies: ["EntityRecognition", "VaultFormat"]),
        .target(name: "VaultFormat"),
        .testTarget(name: "VaultFormatTests", dependencies: ["VaultFormat"]),
        .target(
            name: "VaultIndex",
            dependencies: [
                "VaultFormat", "EntityRecognition", "GoalTracking", .product(name: "GRDB", package: "GRDB.swift"),
            ]),
        .testTarget(
            name: "VaultIndexTests",
            dependencies: [
                "VaultIndex", "EntityRecognition", "GoalTracking", .product(name: "GRDB", package: "GRDB.swift"),
            ]),
    ]
)
