// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileWheel",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FileWheel", targets: ["FileWheel"])],
    targets: [
        .executableTarget(name: "FileWheel"),
        .testTarget(name: "FileWheelTests", dependencies: ["FileWheel"])
    ]
)
