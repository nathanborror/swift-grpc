# Swfit gRPC

A very simple [gRPC](http://www.grpc.io) library to use with Apple's [swift-protobuf](https://github.com/apple/swift-protobuf). **Very much a work in progress**

## Usage

Protobuf outline:

```protobuf
syntax = "proto3";

service HelloService {
  rpc Send(HelloRequest) returns (HelloResponse) {}
}

message HelloRequest {
  string text = 1;
}

message HelloResponse {
  string text = 1;
}
```

Build protobuf file with [swift-protobuf-plugin](https://github.com/apple/swift-protobuf-plugin) and whatever server-side plugin of your choosing, here I'm using Go:

    $ protoc --swift_out=YourSwiftClient/Sources --go_out=plugins=grpc:. your-protobuf-file.proto

Quick and scrappy example:

```swift
import Foundation

let url = URL(string: "http://localhost:8080")!
let grpc = GRPC(url: url)

while !grpc.isConnected {
    sleep(1)
}

let hello = HelloRequest(text: "Hello, World")
grpc.write(path: "/HelloService/Send", data: hello) { (bytes) in
    let resp = try? HelloResponse(protobufBytes: bytes)
    print(resp)
}

sleep(5)
```

Stay tuned 📺
