// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Tools",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: "../RPC"),
        .package(path: "../TracingUtils"),
        .package(path: "../Utils"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/ajevans99/swift-json-schema.git", from: "0.3.2"),
        .package(url: "https://github.com/wickwirew/Runtime.git", from: "2.2.7"),
    ],
    targets: [
        .executableTarget(
            name: "Tools",
            dependencies: [
                "RPC",
                "Utils",
                "TracingUtils",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
                .product(name: "Runtime", package: "Runtime"),
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
