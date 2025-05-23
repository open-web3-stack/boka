// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Codec",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Codec",
            targets: ["Codec"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", branch: "6.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Codec",
            dependencies: []
        ),
        .testTarget(
            name: "CodecTests",
            dependencies: [
                "Codec",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
