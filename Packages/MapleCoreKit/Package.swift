// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MapleCoreKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MapleCoreKit", targets: ["MapleCoreKit"])
    ],
    targets: [
        .target(name: "MapleCoreKit"),
        .testTarget(name: "MapleCoreKitTests", dependencies: ["MapleCoreKit"])
    ]
)
