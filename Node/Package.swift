// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Node",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Node",
            targets: ["Node"]
        ),
    ],
    dependencies: [.package(path: "../Blockchain")],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Node", dependencies: ["Blockchain"]
        ),
        .testTarget(
            name: "NodeTests",
            dependencies: ["Node"]
        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
