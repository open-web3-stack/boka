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
            dependencies: [],
            path: "Sources",
            exclude: [
                "asmjit/asmjit/asmjit.natvis",
            ],
            sources: [
                "CppHelper/a64_labeled_helper.cpp",
                "CppHelper/helper.cpp",
                "CppHelper/instruction_decoder.cpp",
                "CppHelper/instruction_dispatcher.cpp",
                "CppHelper/instructions.cpp",
                "CppHelper/jit_cfg_helper.cpp",
                "CppHelper/jit_control_flow.cpp",
                "CppHelper/jit_exports.cpp",
                "CppHelper/x64_labeled_helper.cpp",
                "asmjit/asmjit",
            ],
            publicHeadersPath: "CppHelper/include",
            cxxSettings: [
                .headerSearchPath("asmjit"),
                .define("ASMJIT_STATIC"),
            ],
        ),
    ],
    swiftLanguageModes: [.version("6")],
    cxxLanguageStandard: .cxx20,
)
