// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
        .package(url: "https://github.com/tesseract-one/ScaleCodec.swift.git", from: "0.3.0"),
        .package(url: "https://github.com/tesseract-one/Blake2.swift.git", from: "0.2.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "4.0.0"),
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
                "blst",
            ]
        ),
        .target(
            name: "blst",
            dependencies: [],
            path: "./Sources/blst",
            exclude: [
                ".github",
                "./build",
                "./src",
            ],
            sources: [],
            publicHeadersPath: "./include",
            cSettings: [
                .headerSearchPath("./include"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L../Utils/Sources/blst/lib", "-lblst"]),
            ]
        ),
        .testTarget(
            name: "UtilsTests",
            dependencies: ["Utils", "blst"]
        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
