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
        .package(path: "../Utils"),
        .package(url: "https://github.com/tesseract-one/ScaleCodec.swift.git", from: "0.3.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/gh123man/Async-Channels", revision: "679ee7d"),
        .package(url: "https://github.com/apple/swift-corelibs-foundation.git", revision: "ca3669eb9ac282c649e71824d9357dbe140c8251"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Blockchain",
            dependencies: [
                .product(name: "Utils", package: "Utils"),
                .product(name: "ScaleCodec", package: "ScaleCodec.swift"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "AsyncChannels", package: "Async-Channels"),
                .product(name: "Foundation", package: "swift-corelibs-foundation"),
            ]
        ),
        .testTarget(
            name: "BlockchainTests",
            dependencies: ["Blockchain"]
        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
