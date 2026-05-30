// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-actor-runtime",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ActorRuntime",
            targets: ["ActorRuntime"]
        ),
    ],
    dependencies: [
        // No external dependencies - pure Swift standard library
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ActorRuntime",
            dependencies: []
        ),
        .testTarget(
            name: "ActorRuntimeTests",
            dependencies: ["ActorRuntime"],
            path: "Tests/ActorRuntimeTests"
        ),
    ]
)
