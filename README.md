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

Fill out gRPC service methods in your swift client:

```swift
import Foundation
import SwiftGRPC

class HelloService {
  
  let client = GRPCClient<HelloResponse>(url: "http://localhost:8080")

  func send(inbound: HelloRequest, callback: @escaping (HelloResponse?, Error?) -> Void) {
    client.post("/HelloService/Send", flags: .endHeaders)
      .data(inbound, flags: 0, callback: callback)
  }
}
```

Use service:

```swift
let service = HelloService()

let hello = HelloRequest(text: "Hello gRPC!")
service.send(inbound: hello) { account, error in
  print(account)
}
```

Stay tuned 📺
