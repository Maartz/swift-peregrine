// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-peregrine",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Peregrine", targets: ["Peregrine"]),
        .library(name: "PeregrineTest", targets: ["PeregrineTest"]),
        .executable(name: "peregrine", targets: ["PeregrineCLI"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Spectro-ORM/Spectro.git",
            from: "1.2.0"
        ),
        .package(
            url: "https://github.com/Spectro-ORM/Nexus.git",
            from: "1.3.0"
        ),
        .package(
            url: "https://github.com/Spectro-ORM/ESW.git",
            from: "1.2.0"
        ),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.2.0"
        ),
        .package(
            url: "https://github.com/tuist/Noora",
            .upToNextMajor(from: "0.15.0")
        ),
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            from: "3.0.0"
        ),
        .package(
            url: "https://github.com/apple/swift-metrics.git",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/apple/swift-distributed-tracing.git",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.0.0"
        ),
    ],
    targets: [
        .target(
            name: "Peregrine",
            dependencies: [
                .product(name: "SpectroKit", package: "Spectro"),
                .product(name: "Nexus", package: "Nexus"),
                .product(name: "NexusRouter", package: "Nexus"),
                .product(name: "NexusHummingbird", package: "Nexus"),
                .product(name: "NexusTest", package: "Nexus"),
                .product(name: "ESW", package: "esw"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "PeregrineTest",
            dependencies: [
                "Peregrine",
                .product(name: "NexusTest", package: "Nexus"),
            ]
        ),
        .executableTarget(
            name: "PeregrineCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Noora", package: "Noora"),
            ]
        ),
        .testTarget(
            name: "PeregrineTests",
            dependencies: [
                "Peregrine",
                "PeregrineTest",
                .product(name: "NexusTest", package: "Nexus"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
    ]
)
