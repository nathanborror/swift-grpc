import PackageDescription

let package = Package(
    name: "SwiftGRPC",
    dependencies: [
      .Package(url: "https://github.com/apple/swift-protobuf-runtime.git", Version(0,9,21)),
    ]
)
