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
        .package(path: "../TracingUtils"),
        .package(url: "https://github.com/slashmo/swift-otel.git", from: "0.9.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
        .package(url: "https://github.com/vapor/console-kit.git", from: "4.15.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Boka",
            dependencies: [
                "Node",
                "TracingUtils",
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "OTel", package: "swift-otel"),
                .product(name: "OTLPGRPC", package: "swift-otel"),
                .product(name: "ConsoleKit", package: "console-kit"),
            ]
        ),
        .testTarget(
            name: "BokaTests",
            dependencies: ["Boka"]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
