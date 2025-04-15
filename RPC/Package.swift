// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RPC",
    platforms: [
        .macOS(.v15),
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
        .package(path: "../Utils"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.106.0"),
        .package(url: "https://github.com/vapor/async-kit.git", from: "1.20.0"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "6.0.3"),

    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "RPC",
            dependencies: [
                "Blockchain",
                "Utils",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "AsyncKit", package: "async-kit"),
            ]
        ),
        .testTarget(
            name: "RPCTests",
            dependencies: [
                .target(name: "RPC"),
                .product(name: "XCTVapor", package: "vapor"),
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
