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
            targets: ["PolkaVM"],
        ),
        .executable(
            name: "boka-sandbox",
            targets: ["Sandbox"],
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
            cSettings: [
                .headerSearchPath("../asmjit"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ],
        ),
        .target(
            name: "MacOSSandboxSupport",
            path: "Sources/MacOSSandboxSupport",
            publicHeadersPath: "include",
        ),
        .executableTarget(
            name: "Sandbox",
            dependencies: [
                "PolkaVM",
                "Utils",
                "TracingUtils",
                "MacOSSandboxSupport",
                .product(name: "Logging", package: "swift-log"),
            ],
            sources: ["main.swift"],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ],
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
            ],
        ),
        .target(
            name: "CppHelper",
            dependencies: [
            ],
            exclude: [
                "asmjit/tools",
                "asmjit/.github",
                "asmjit/db",
                "asmjit/asmjit-testing",
                "asmjit/module.modulemap",
                "asmjit/configure.sh",
                "asmjit/configure_sanitizers.sh",
                "asmjit/configure_vs2022_x64.bat",
                "asmjit/configure_vs2022_x86.bat",
                "asmjit/CMakeLists.txt",
                "asmjit/CMakePresets.json",
                "asmjit/.git",
                "asmjit/.gitignore",
                "asmjit/.editorconfig",
                "asmjit/LICENSE.md",
                "asmjit/README.md",
                "asmjit/CONTRIBUTING.md",
                "asmjit/asmjit/asmjit.natvis",
                "asmjit/include",
            ],
            sources: ["."],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("asmjit"),
                .unsafeFlags([
                    "-std=c++20",
                ]),
                .define("ASMJIT_STATIC"),
            ],
        ),
    ],
    swiftLanguageModes: [.version("6")],
)
