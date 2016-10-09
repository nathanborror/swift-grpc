# Swift gRPC

A very simple [gRPC][1] library to use with Apple's [swift-protobuf][2].

---

:warning: There is active work going on here that will result in API changes. :warning:

---

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

Client code:

```swift
import Foundation

let url = URL(string: "http://localhost:8080")!
let session = GrpcSession(url: url)

let hello = HelloRequest(text: "Hello, World")

try? session.write(path: "/HelloService/Send", data: hello) { bytes in
    let resp = try? HelloResponse(protobufBytes: bytes)
    print(resp)
}
```

[1]:http://www.grpc.io
[2]:https://github.com/apple/swift-protobuf
