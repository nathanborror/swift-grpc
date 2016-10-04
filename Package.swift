import PackageDescription

let package = Package(
    name: "SwiftGRPC",
    dependencies: [
        .Package(url: "https://github.com/apple/swift-protobuf.git", majorVersion: 0),
        .Package(url: "https://github.com/nathanborror/hpack.swift.git", majorVersion: 0),
    ]
)
