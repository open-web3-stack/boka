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
        .package(url: "https://github.com/AcalaNetwork/ScaleCodec.swift.git", branch: "main"),
        .package(url: "https://github.com/tesseract-one/Blake2.swift.git", from: "0.2.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "4.0.0"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "0.10.0"),
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
                "bandersnatch_vrfs",
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
        .target(
            name: "bandersnatch_vrfs",
            dependencies: [],
            path: "./Sources/bandersnatch",
            sources: [],
            publicHeadersPath: "./include",
            cSettings: [
                .headerSearchPath("./include"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L../Utils/Sources/bandersnatch/lib",
                    "-lbandersnatch_vrfs",
                ]),
            ]
        ),
        .testTarget(
            name: "UtilsTests",
            dependencies: [
                "Utils", .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
