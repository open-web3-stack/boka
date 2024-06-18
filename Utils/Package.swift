// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Utils",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Utils",
            targets: ["Utils"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-corelibs-foundation.git", revision: "ca3669eb9ac282c649e71824d9357dbe140c8251"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Utils",
            dependencies: [
                .product(name: "Foundation", package: "swift-corelibs-foundation"),
            ]
        ),
        .testTarget(
            name: "UtilsTests",
            dependencies: ["Utils"]
        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
