//
//  SwiftGRPC/Sources/GRPC.swift - GRPC Client
//
//  This source file is part of the SwiftGRPC open source project
//  https://github.com/nathanborror/swift-grpc
//  Created by Nathan Borror on 10/1/16.
//

import Foundation
import SwiftProtobuf

public class GRPC: NSObject {

    public typealias Callback = ([UInt8]) -> Void

    let http: Http2
    var callbacks: [StreamID: Callback]

    public init(url: URL) {
        self.http = Http2(url: url)
        self.callbacks = [:]
        super.init()
        self.http.delegate = self
    }

    public func write(path: String, data: ProtobufMessage, callback: @escaping Callback) {
        self.http.connect()

        let stream = http.streams.next()
        callbacks[stream] = callback

        let headers = [
            (":method", "POST"),
            (":scheme", "http"),
            (":path", path),
            ("content-type", "application/grpc+proto"),
            ("te", "trailers"),
            ]
        let frame = Frame(headers: headers, stream: stream, flags: .endHeaders)
        http.write(frame: frame)

        let payload = try! data.serializeProtobufBytes()
        var bytes: [UInt8] = [0, 0, 0, 0, UInt8(payload.count)]
        bytes += payload

        let dataFrame = Frame(data: bytes, stream: stream, flags: .endStream)
        http.write(frame: dataFrame)
    }
}

extension GRPC: Http2Delegate {

    public func clientConnected(http: Http2) {
    }

    public func client(http: Http2, hasFrame frame: Frame) {

        // Ignore frames with a stream ID of 0
        guard frame.stream > 0 else { return }

        // Process data and send it over callback
        if frame.type == .data {
            guard let payload = frame.payload else { return }
            let bytes = Array(payload[5..<payload.count])
            callbacks[frame.stream]?(bytes)
        }

        // Remove callback when we receive a stream closed flag
        if frame.flags == .streamClosed {
            callbacks.removeValue(forKey: frame.stream)
        }

        // Disconnect if there are no more callbacks
        if callbacks.count == 0 {
            http.disconnect()
        }
    }
}
