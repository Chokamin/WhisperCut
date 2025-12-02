// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AutoFCPXCaptions",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AutoFCPXCaptions", targets: ["AutoFCPXCaptions"])
    ],
    dependencies: [
        // SwiftWhisper 依赖 (基于 whisper.cpp)
        // .package(url: "https://github.com/exPHAT/SwiftWhisper.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "AutoFCPXCaptions",
            dependencies: [
                // "SwiftWhisper"
            ],
            path: ".",
            exclude: ["Package.swift"],
            sources: [
                "App",
                "Models",
                "Services",
                "Views"
            ]
        )
    ]
)
