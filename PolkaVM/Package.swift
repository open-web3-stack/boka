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
        .package(url: "https://github.com/apple/swift-testing.git", branch: "6.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/nicklockwood/LRUCache.git", from: "1.0.7"),
    ],
    targets: [
        .target(
            name: "PolkaVM",
            dependencies: [
                "Utils",
                "TracingUtils",
                "CppHelper",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "LRUCache", package: "LRUCache"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .testTarget(
            name: "PolkaVMTests",
            dependencies: [
                "PolkaVM",
                "CppHelper",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .target(
            name: "CppHelper",
            dependencies: [
                "asmjit",
            ],
            sources: ["."],
            publicHeadersPath: "."
        ),
        .target(
            name: "asmjit",
            sources: ["src/asmjit"],
            publicHeadersPath: "src"
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
