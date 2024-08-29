// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Networking",
            targets: ["Networking"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Networking",
            dependencies: [
                "msquic",
            ],
            swiftSettings: [
                .define("DEBUG_ASSERT", .when(configuration: .debug)),
            ],
            linkerSettings: [
                .unsafeFlags(["-L../.lib"]),
            ]
        ),
        .systemLibrary(
            name: "msquic",
            path: "Sources"
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "Networking",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
