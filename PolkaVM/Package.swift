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
        .package(path: "../Codec"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "6.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "PolkaVM",
            dependencies: [
                "Utils",
                "TracingUtils",
                "Codec",
                "CppHelper",
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .unsafeFlags([
                    "-Xcc", "-std=c++20",
                    "-Xcc", "-I/usr/include/c++/13",
                    "-Xcc", "-I/usr/include/x86_64-linux-gnu/c++/13",
                    "-Xcc", "-I/home/ubuntu/boka/PolkaVM/Sources/asmjit",
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
                    "-Xcc", "-I/home/ubuntu/boka/PolkaVM/Sources/asmjit",
                ]),
            ]
        ),
        .testTarget(
            name: "PolkaVMTests",
            dependencies: [
                "PolkaVM",
                "CppHelper",
                "Codec",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .unsafeFlags([
                    "-Xcc", "-std=c++20",
                    "-Xcc", "-I/usr/include/c++/13",
                    "-Xcc", "-I/usr/include/x86_64-linux-gnu/c++/13",
                    "-Xcc", "-I/home/ubuntu/boka/PolkaVM/Sources/asmjit",
                ]),
            ]
        ),
        .target(
            name: "CppHelper",
            dependencies: [
            ],
            exclude: [
                "asmjit/asmjit.natvis",
                "asmjit/include/asmjit.natvis",
                "asmjit/asmjit/asmjit.natvis",
                "asmjit/.git",
                "asmjit/.github",
                "asmjit/CMakeLists.txt",
                "asmjit/asmjit-testing",
                "asmjit/tools",
                "asmjit/db",
                "asmjit/module.modulemap",
                "asmjit/LICENSE.md",
                "asmjit/README.md",
                "asmjit/CONTRIBUTING.md",
                "asmjit/configure.sh",
                "asmjit/configure_sanitizers.sh",
                "asmjit/configure_vs2022_x86.bat",
                "asmjit/configure_vs2022_x64.bat",
                "asmjit/CMakePresets.json",
                "asmjit/include",
            ],
            sources: [
                ".",
                "../asmjit/asmjit/core",
                "../asmjit/asmjit/arm",
                "../asmjit/asmjit/x86",
                "../asmjit/asmjit/support",
                "../asmjit/asmjit/ujit",
            ],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("../../Sources/asmjit"),
                .unsafeFlags([
                    "-std=c++20",
                    "-I/usr/include/c++/13",
                    "-I/usr/include/x86_64-linux-gnu/c++/13",
                    "-I/home/ubuntu/boka/PolkaVM/Sources/asmjit",
                ]),
                .define("ASMJIT_STATIC"),
            ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
