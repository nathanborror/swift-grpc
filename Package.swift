import PackageDescription

let package = Package(
    name: "SwiftGRPC",
    dependencies: [
        .Package(url: "https://github.com/apple/swift-protobuf.git", majorVersion: 0),
    ]
)
