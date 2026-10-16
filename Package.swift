// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FruitWave",
    platforms: [.macOS(.v14), .tvOS(.v17)],
    products: [
        .library(name: "FruitWaveCore", targets: ["FruitWaveCore"])
    ],
    targets: [
        .target(name: "FruitWaveCore"),
        .testTarget(name: "FruitWaveCoreTests", dependencies: ["FruitWaveCore"])
    ]
)
