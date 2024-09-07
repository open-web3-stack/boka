// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PVMShell",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "PVMShell",
            targets: ["PVMShell"]
        ),
    ],
    dependencies: [
        .package(path: "../PolkaVM"),
    ],
    targets: [
        .target(
            name: "PVMShell",
            dependencies: [
                "PolkaVM",
            ]

        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
