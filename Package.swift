// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "MLFinder",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "MLFinder", path: "Sources/MLFinder")]
)
