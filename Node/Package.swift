// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Node",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Node",
            targets: ["Node"]
        ),
    ],
    dependencies: [
        .package(path: "../Blockchain"),
        .package(path: "../Networking"),
        .package(path: "../RPC"),
        .package(path: "../TracingUtils"),
        .package(path: "../Utils"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "0.10.0"),
        .package(url: "https://github.com/gh123man/Async-Channels.git", from: "1.0.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Node", dependencies: [
                "Blockchain",
                "Networking",
                "RPC",
                "TracingUtils",
                "Utils",
                .product(name: "AsyncChannels", package: "Async-Channels"),
            ]
        ),
        .testTarget(
            name: "NodeTests",
            dependencies: [
                "Node",
                .product(name: "Testing", package: "swift-testing"),
            ],
            resources: [
                .copy("chainfiles"),
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
