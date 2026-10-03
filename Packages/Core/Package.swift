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
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "VaultFormat"),
        .testTarget(name: "VaultFormatTests", dependencies: ["VaultFormat"]),
        .target(name: "VaultIndex", dependencies: ["VaultFormat", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(
            name: "VaultIndexTests", dependencies: ["VaultIndex", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
