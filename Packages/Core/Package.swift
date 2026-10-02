// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "VaultFormat", targets: ["VaultFormat"])
    ],
    targets: [
        .target(name: "VaultFormat"),
        .testTarget(name: "VaultFormatTests", dependencies: ["VaultFormat"]),
    ]
)
