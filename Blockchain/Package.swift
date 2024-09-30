// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Blockchain",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Blockchain",
            targets: ["Blockchain"]
        ),
    ],
    dependencies: [
        .package(path: "../Codec"),
        .package(path: "../Utils"),
        .package(path: "../TracingUtils"),
        .package(path: "../PolkaVM"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "0.10.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Blockchain",
            dependencies: [
                "Codec",
                "Utils",
                "PolkaVM",
                "TracingUtils",
            ]
        ),
        .testTarget(
            name: "BlockchainTests",
            dependencies: [
                "Blockchain",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
