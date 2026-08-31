// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Minutes",
    platforms: [.macOS(.v15)],
    dependencies: [
        // AD-15: pinned exact. Verified from the manifest at this tag.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0"),
        // NVIDIA Parakeet TDT via CoreML. A second transcription engine, roughly
        // an order of magnitude faster than Whisper on Apple Silicon.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.6"),
    ],
    targets: [
        .executableTarget(
            name: "Minutes",
            dependencies: [
                // Link the two products we use, never the ArgmaxOSS umbrella (it drags in TTSKit).
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Minutes",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MinutesTests",
            dependencies: ["Minutes"],
            path: "Tests/MinutesTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
