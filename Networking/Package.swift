// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Networking",
            targets: ["Networking"]
        ),
    ],
    dependencies: [
        .package(path: "../Utils"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "0.10.0"),
    ],
    targets: [
        .target(
            name: "Networking",
            dependencies: [
                "MsQuicSwift",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "X509", package: "swift-certificates"),
            ]
        ),
        .target(
            name: "CHelpers",
            dependencies: [
                "openssl",
            ],
            sources: ["helpers.h", "helpers.c"],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../include"),
            ]
        ),
        .target(
            name: "MsQuicSwift",
            dependencies: [
                "msquic",
                "Utils",
                "CHelpers",
                .product(name: "Logging", package: "swift-log"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L../.lib"]),
            ]
        ),
        .systemLibrary(
            name: "msquic",
            path: "Sources"
        ),
        .systemLibrary(
            name: "openssl",
            path: "Sources"
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "Networking",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "MsQuicSwiftTests",
            dependencies: [
                "MsQuicSwift",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
