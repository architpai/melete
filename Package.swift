// swift-tools-version:6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Melete",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Melete", targets: ["Melete"])],
    targets: [
        .target(name: "MeleteCore", swiftSettings: v5),
        .executableTarget(name: "Melete", dependencies: ["MeleteCore"], swiftSettings: v5),
        .testTarget(name: "MeleteCoreTests", dependencies: ["MeleteCore"], swiftSettings: v5),
    ]
)
