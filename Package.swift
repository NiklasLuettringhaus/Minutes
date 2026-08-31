// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Minutes",
    platforms: [.macOS(.v15)],
    dependencies: [
        // AD-15: pinned exact. Verified from the manifest at this tag.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Minutes",
            dependencies: [
                // Link the two products we use, never the ArgmaxOSS umbrella (it drags in TTSKit).
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
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
