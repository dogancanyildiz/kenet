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
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "VaultStore", dependencies: ["VaultFormat", "VaultIndex"]),
        .testTarget(
            name: "VaultStoreTests",
            dependencies: ["VaultStore", "VaultIndex", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "DateParsing", dependencies: ["VaultFormat"]),
        .testTarget(name: "DateParsingTests", dependencies: ["DateParsing", "VaultFormat"]),
        .target(name: "EntityRecognition", dependencies: ["VaultFormat"]),
        .testTarget(name: "EntityRecognitionTests", dependencies: ["EntityRecognition", "VaultFormat"]),
        .target(name: "VaultFormat"),
        .testTarget(name: "VaultFormatTests", dependencies: ["VaultFormat"]),
        .target(
            name: "VaultIndex",
            dependencies: ["VaultFormat", "EntityRecognition", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(
            name: "VaultIndexTests",
            dependencies: ["VaultIndex", "EntityRecognition", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
