// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PVMShell",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../PolkaVM"),
        .package(path: "../Utils"),
    ],
    targets: [
        .executableTarget(
            name: "PVMShell",
            dependencies: [
                "PolkaVM",
                "Utils",
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
