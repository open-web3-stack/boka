// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let packageDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .path
let asmJitIncludePath = "\(packageDirectory)/Sources/asmjit"

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
                "AsmJitLib",
                "CppHelper",
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .unsafeFlags([
                    "-Xcc",
                    "-I\(asmJitIncludePath)",
                ]),
            ],
        ),
        .target(
            name: "AsmJitLib",
            dependencies: [],
            path: "Sources/asmjit",
            exclude: [
                "tools",
                ".github",
                "db",
                "asmjit-testing",
                "configure.sh",
                "configure_sanitizers.sh",
                "configure_vs2022_x64.bat",
                "configure_vs2022_x86.bat",
                "CMakeLists.txt",
                "CMakePresets.json",
                ".git",
                ".gitignore",
                ".editorconfig",
                "LICENSE.md",
                "README.md",
                "CONTRIBUTING.md",
                "asmjit/asmjit.natvis",
            ],
            sources: ["asmjit"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .unsafeFlags([
                    "-std=c++20",
                ]),
                .define("ASMJIT_STATIC"),
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
            linkerSettings: [
                // Rust staticlibs can export duplicate runtime symbols (e.g. rust_eh_personality)
                // across archives; GNU ld rejects these by default.
                .unsafeFlags(["-Xlinker", "--allow-multiple-definition"], .when(platforms: [.linux])),
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
                "AsmJitLib",
            ],
            exclude: [
                ".DS_Store",
            ],
            sources: [
                "a64_labeled_helper.cpp",
                "helper.cpp",
                "instruction_decoder.cpp",
                "instruction_dispatcher.cpp",
                "instructions.cpp",
                "jit_cfg_helper.cpp",
                "jit_control_flow.cpp",
                "jit_exports.cpp",
                "x64_labeled_helper.cpp",
            ],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("../asmjit"),
                .unsafeFlags([
                    "-std=c++20",
                ]),
            ],
        ),
    ],
    swiftLanguageModes: [.version("6")],
)
