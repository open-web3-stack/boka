// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Utils",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Utils",
            targets: ["Utils"]
        ),
    ],
    dependencies: [
        .package(path: "../Codec"),
        .package(path: "../TracingUtils"),
        .package(url: "https://github.com/tesseract-one/Blake2.swift.git", from: "0.2.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "4.0.0"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "0.10.0"),
        .package(url: "https://github.com/qiweiii/swift-numerics.git", branch: "wasm-fix"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Utils",
            dependencies: [
                "Codec",
                "TracingUtils",
                .product(name: "Blake2", package: "Blake2.swift"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Numerics", package: "swift-numerics"),
                "bls",
                "bandersnatch_vrfs",
                "erasure_coding",
                "SHA3IUF",
            ],
            swiftSettings: [
                .define("DEBUG_ASSERT", .when(configuration: .debug)),
            ],
            linkerSettings: [
                .unsafeFlags(["-L../.lib"]),
            ]
        ),
        .target(
            name: "SHA3IUF",
            sources: ["sha3.h", "sha3.c"],
            publicHeadersPath: "."
        ),
        .systemLibrary(
            name: "bls",
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
    swiftLanguageModes: [.version("6")]
)
