// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

// somehow without this the GH Actions CI fails
extension Foundation.Bundle: @unchecked @retroactive Sendable {}

let package = Package(
    name: "Utils",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Utils",
            targets: ["Utils"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/AcalaNetwork/ScaleCodec.swift.git", branch: "main"),
        .package(url: "https://github.com/tesseract-one/Blake2.swift.git", from: "0.2.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "4.0.0"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "0.10.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Utils",
            dependencies: [
                .product(name: "ScaleCodec", package: "ScaleCodec.swift"),
                .product(name: "Blake2", package: "Blake2.swift"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Atomics", package: "swift-atomics"),
                "blst",
                "bandersnatch_vrfs",
                "erasure_coding",
            ],
            swiftSettings: [
                .define("DEBUG_ASSERT", .when(configuration: .debug)),
            ],
            linkerSettings: [
                .unsafeFlags(["-L../.lib"]),
            ]
        ),
        .systemLibrary(
            name: "blst",
            path: "Sources"
        ),
        .systemLibrary(
            name: "bandersnatch_vrfs",
            path: "Sources"
        ),
        .systemLibrary(
            name: "erasure_coding",
            path: "Sources"
        ),
        .testTarget(
            name: "UtilsTests",
            dependencies: [
                "Utils",
                .product(name: "Testing", package: "swift-testing"),
            ],
            resources: [.copy("TestData")]
        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
