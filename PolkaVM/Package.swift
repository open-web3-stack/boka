// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PolkaVM",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "PolkaVM",
            targets: ["PolkaVM"]
        ),
        .executable(
            name: "boka-sandbox",
            targets: ["Sandbox"]
        ),
    ],
    dependencies: [
        .package(path: "../Utils"),
        .package(path: "../TracingUtils"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "6.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "PolkaVM",
            dependencies: [
                "Utils",
                "TracingUtils",
                "CppHelper",
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .unsafeFlags([
                    "-Xcc", "-std=c++20",
                    "-Xcc", "-I/usr/include/c++/13",
                    "-Xcc", "-I/usr/include/x86_64-linux-gnu/c++/13",
                    "-Xcc", "-I/home/ubuntu/boka/PolkaVM/Sources/asmjit"
                ]),
            ]
        ),
        .executableTarget(
            name: "Sandbox",
            dependencies: [
                "PolkaVM",
                "Utils",
                "TracingUtils",
                .product(name: "Logging", package: "swift-log"),
            ],
            sources: ["main.swift"],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .enableExperimentalFeature("StrictConcurrency=minimal"),
                .unsafeFlags([
                    "-Xcc", "-std=c++20",
                    "-Xcc", "-I/usr/include/c++/13",
                    "-Xcc", "-I/usr/include/x86_64-linux-gnu/c++/13",
                    "-Xcc", "-I/home/ubuntu/boka/PolkaVM/Sources/asmjit"
                ]),
            ]
        ),
        .testTarget(
            name: "PolkaVMTests",
            dependencies: [
                "PolkaVM",
                "CppHelper",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .unsafeFlags([
                    "-Xcc", "-std=c++20",
                    "-Xcc", "-I/usr/include/c++/13",
                    "-Xcc", "-I/usr/include/x86_64-linux-gnu/c++/13",
                    "-Xcc", "-I/home/ubuntu/boka/PolkaVM/Sources/asmjit"
                ]),
            ]
        ),
        .target(
            name: "CppHelper",
            dependencies: [
            ],
            exclude: ["asmjit/asmjit.natvis", "asmjit/.git", "asmjit/.github", "asmjit/CMakeLists.txt", "asmjit/asmjit-testing"],
            sources: [".", "../asmjit/asmjit/core", "../asmjit/asmjit/arm", "../asmjit/asmjit/x86", "../asmjit/asmjit/support", "../asmjit/asmjit/ujit"],
            publicHeadersPath: ".",
            cxxSettings: [
                .unsafeFlags([
                    "-std=c++20",
                    "-I/usr/include/c++/13",
                    "-I/usr/include/x86_64-linux-gnu/c++/13",
                    "-I../asmjit"
                ]),
                .define("ASMJIT_STATIC"),
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
