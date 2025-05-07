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
        .package(path: "../Blockchain"),
        .package(path: "../Codec"),
        .package(path: "../Utils"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "6.0.0"),
    ],
    targets: [
        .target(
            name: "Database",
            dependencies: [
                "RocksDBSwift",
                "Blockchain",
                "Codec",
                "Utils",
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .target(
            name: "RocksDBSwift",
            dependencies: [
                "rocksdb",
                "Utils",
            ],
            linkerSettings: [
                .unsafeFlags(["-L../.lib", "-L/opt/homebrew/lib"]),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("zstd"),
                .linkedLibrary("lz4"),
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
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .testTarget(
            name: "RocksDBSwiftTests",
            dependencies: [
                "RocksDBSwift",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
