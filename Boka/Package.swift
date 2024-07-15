// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Boka",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../Node"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.4.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Boka",
            dependencies: [
                "Node",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L../Utils/Sources/blst/lib"]),
            ]
        ),
        .testTarget(
            name: "BokaTests",
            dependencies: ["Boka"],
            linkerSettings: [
                .unsafeFlags(["-L../Utils/Sources/blst/lib"]),
            ]
        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
