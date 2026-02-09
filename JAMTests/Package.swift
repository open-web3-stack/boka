// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JAMTests",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "JAMTests",
            targets: ["JAMTests"],
        ),
    ],
    dependencies: [
        .package(path: "../Codec"),
        .package(path: "../Utils"),
        .package(path: "../TracingUtils"),
        .package(path: "../Blockchain"),
        .package(path: "../PolkaVM"),
        .package(path: "../Database"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "6.0.0"),
        .package(url: "https://github.com/ordo-one/package-benchmark.git", .upToNextMajor(from: "1.29.4")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "JAMTests",
            dependencies: [
                "Blockchain",
            ],
            resources: [
                .copy("../../jamtestvectors"),
                .copy("../../jamduna"),
                .copy("../../javajam"),
                .copy("../../fuzz"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ],
        ),
        .testTarget(
            name: "JAMTestsTests",
            dependencies: [
                "Codec",
                "Utils",
                "TracingUtils",
                "Blockchain",
                "PolkaVM",
                "JAMTests",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ],
        ),
        .executableTarget(
            name: "Benchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                "Blockchain",
                "Codec",
                "Database",
                "JAMTests",
                "PolkaVM",
                "Utils",
            ],
            path: "Benchmarks/Benchmarks",
            cxxSettings: [
                .unsafeFlags(["-Wno-incomplete-umbrella"]),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ],
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark"),
            ],
        ),
    ],
    swiftLanguageModes: [.version("6")],
)
