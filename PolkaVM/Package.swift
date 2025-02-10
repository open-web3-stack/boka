// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PolkaVM",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "PolkaVM",
            targets: ["PolkaVM"]
        ),
    ],
    dependencies: [
        .package(path: "../Utils"),
        .package(path: "../TracingUtils"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "0.10.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/qiweiii/LRUCache.git", branch: "no-notification"),
    ],
    targets: [
        .target(
            name: "PolkaVM",
            dependencies: [
                "Utils",
                "TracingUtils",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "LRUCache", package: "LRUCache"),
            ]
        ),
        .testTarget(
            name: "PolkaVMTests",
            dependencies: [
                "PolkaVM",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
