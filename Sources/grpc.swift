//
//  SwiftGRPC/Sources/GRPC.swift - GRPC Client
//
//  This source file is part of the SwiftGRPC open source project
//  https://github.com/nathanborror/swift-grpc
//  Created by Nathan Borror on 10/1/16.
//

import Foundation
import SwiftProtobuf
import SwiftHttp2

enum HeaderField: String {
    case method = ":method"
    case scheme = ":scheme"
    case path = ":path"
    case contentType = "content-type"
    case te = "te"
    case token = "token"
}

public class GrpcSession: NSObject {

    public typealias Callback = ([UInt8]) -> Void

    let url: URL
    let session: Http2Session
    var callbacks: [StreamID: Callback]

    public init(url: URL) {
        self.url = url
        self.session = Http2Session(url: url)
        self.callbacks = [:]

        super.init()

        self.session.delegate = self
    }

    public func write(path: String, data: ProtobufMessage, token: String? = nil, callback: @escaping Callback) throws {
        self.session.connect()

        let stream = session.streams.next()
        callbacks[stream] = callback

        var headers: [(HeaderField, String)] = [
            (.method, "POST"),
            (.scheme, url.scheme ?? "http"),
            (.path, path),
            (.contentType, "application/grpc+proto"),
            (.te, "trailers"),
            ]
        if let token = token {
            headers.append((.token, token))
        }

        let frame = Frame(headers: headers.map { ($0.0.rawValue, $0.1) }, stream: stream, flags: .endHeaders)
        try session.write(frame: frame)

        let payload = try! data.serializeProtobufBytes()
        var bytes: [UInt8] = [0, 0, 0, 0, UInt8(payload.count)]
        bytes += payload

        let dataFrame = Frame(data: bytes, stream: stream, flags: .endStream)
        try session.write(frame: dataFrame)
    }
}

extension GrpcSession: Http2SessionDelegate {

    public func sessionConnected(session: Http2Session) {
    }

    public func session(session: Http2Session, hasFrame frame: Frame) {

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
            session.disconnect()
        }
    }
}
