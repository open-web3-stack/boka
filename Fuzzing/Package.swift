// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Fuzzing",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Fuzzing",
            targets: ["Fuzzing"]
        ),
    ],
    dependencies: [
        .package(path: "../Blockchain"),
        .package(path: "../Codec"),
        .package(path: "../TracingUtils"),
        .package(path: "../Utils"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "6.0.0"),
    ],
    targets: [
        .target(
            name: "Fuzzing",
            dependencies: [
                "Blockchain",
                "Codec",
                "TracingUtils",
                "Utils",
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .testTarget(
            name: "FuzzingTests",
            dependencies: [
                "Fuzzing",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
