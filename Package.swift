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
    ],
    dependencies: [
        .package(path: "../Spectro"),
        .package(path: "../Nexus"),
        .package(path: "../esw"),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.0.0"
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
            ]
        ),
        .target(
            name: "PeregrineTest",
            dependencies: [
                "Peregrine",
                .product(name: "NexusTest", package: "Nexus"),
            ]
        ),
        .testTarget(
            name: "PeregrineTests",
            dependencies: ["Peregrine", "PeregrineTest"]
        ),
    ]
)
