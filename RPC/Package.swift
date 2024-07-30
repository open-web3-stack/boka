// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RPC",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "RPC",
            targets: ["RPC"]
        ),
    ],
    dependencies: [
        .package(path: "../Blockchain"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.102.1"),
        .package(url: "https://github.com/vapor/async-kit.git", from: "1.19.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "RPC",
            dependencies: [
                "Blockchain",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "AsyncKit", package: "async-kit"),
            ]
        ),
        .testTarget(
            name: "RPCTests",
            dependencies: [
                .target(name: "RPC"),
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
