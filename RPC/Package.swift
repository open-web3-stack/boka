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
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "RPC",
            dependencies: [
                "Blockchain",
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .testTarget(
            name: "RPCTests",
            dependencies: ["RPC"]
        ),
    ]
)
