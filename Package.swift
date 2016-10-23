import PackageDescription

let package = Package(
    name: "SwiftGRPC",
    dependencies: [
        .Package(url: "https://github.com/nathanborror/swift-protobuf.git", Version(0, 9, 25)),
        .Package(url: "https://github.com/nathanborror/swift-http2.git", Version(0, 1, 3)),
    ]
)
