// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Database",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Database",
            targets: ["Database"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", branch: "0.10.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Database",
            dependencies: [
                "rocksdb",
            ],
            linkerSettings: [
                .unsafeFlags(["-L../.lib", "-L/opt/homebrew/lib"]),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("zstd"),
            ]
        ),
        .systemLibrary(
            name: "rocksdb",
            path: "Sources"
        ),
        .testTarget(
            name: "DatabaseTests",
            dependencies: [
                "Database",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
