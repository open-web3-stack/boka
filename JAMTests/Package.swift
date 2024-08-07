// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JAMTests",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "JAMTests",
            targets: ["JAMTests"]
        ),
    ],
    dependencies: [
        .package(path: "../Utils"),
        .package(path: "../Blockchain"),
        .package(path: "../PolkaVM"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "0.10.0"),
        .package(url: "https://github.com/AcalaNetwork/ScaleCodec.swift.git", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "JAMTests",
            resources: [.copy("../../jamtestvectors")]
        ),
        .testTarget(
            name: "JAMTestsTests",
            dependencies: [
                "Utils",
                "Blockchain",
                "PolkaVM",
                "JAMTests",
                .product(name: "Testing", package: "swift-testing"),
                .product(name: "ScaleCodec", package: "ScaleCodec.swift"),
            ]
        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
