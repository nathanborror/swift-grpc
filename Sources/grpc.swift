//
//  SwiftGRPC/Sources/gRPC.swift - GRPC Client
//
//  This source file is part of the SwiftGRPC open source project
//  https://github.com/nathanborror/swift-grpc
//  Created by Nathan Borror on 10/1/16.
//

import Foundation
import Protobuf

public class GRPC<T: ProtobufMessage> {

    public typealias ResponseHandler = (() throws -> T) -> Void

    let session: URLSession
    let scheme: String
    let host: String
    let port: Int

    var task: URLSessionStreamTask

    private var streams: HttpStream
    private let timeout: TimeInterval = 0
    private let minReadLength: Int = 0
    private let maxReadLength: Int = 1024

    public init(url: String) {
        guard let url = URL(string: url) else { fatalError() }
        self.session = URLSession(configuration: .default)
        self.scheme = url.scheme ?? "http"
        self.host = url.host ?? ""
        self.port = url.port ?? 80
        self.streams = HttpStream()

        self.task = session.streamTask(withHostName: host, port: port)
        self.task.resume()

        HttpFrame.preface(task: task)
        HttpFrame.settings(flags: .settingsAck).write(to: task)
    }

    public func newStream() -> UInt32 {
        let streamId = streams.new()
        streams.streams[streamId] = .idle
        return streamId
    }

    @discardableResult
    public func call(path: String, stream: UInt32, flags: HttpFlag = .endHeaders) -> Self {
        let headers = [
            (":method", "POST"),
            (":scheme", scheme),
            (":path", path),
            (":authority", host),
            ("content-type", "application/grpc+proto"),
            ("user-agent", "grpc-swift/1.0"),
            ("te", "trailers"),
            ]
        HttpFrame.send(headers: headers, flags: flags, stream: stream).write(to: task)
        return self
    }

    func handleHeader(frame: HttpFrame) {
        let decoder = HPACKDecoder()
        let listener = HttpHeaderDecoder()
        let bytes = Bytes(existingBytes: frame.payload ?? [])
        do {
            try decoder.decode(input: bytes, headerListener: listener)
            print(listener.headers)
        } catch {
            print(error, listener.headers)
        }
    }

    func handleData(frame: HttpFrame, then: @escaping ResponseHandler) {
        let b = Array(frame.payload![5..<frame.payload!.count])
        let data = Data(bytes: b, count: b.count)
        do {
            let out = try T(protobuf: data)
            then { return out }
        } catch {
            then { throw error }
        }
    }

    func close() {
        task.closeWrite()
    }
}

public class UnaryClient<T: ProtobufMessage>: GRPC<T> {

    public override init(url: String) {
        super.init(url: url)
    }

    @discardableResult
    public func with(data: ProtobufMessage, stream: UInt32, flags: HttpFlag = 0, then: @escaping ResponseHandler) -> Self {
        task.readData(ofMinLength: 0, maxLength: 1024, timeout: 0) { (data, isEOF, error) in
            let frames = HttpFrame.read(data)
            for frame in frames {
                switch frame.type {
                case .data:     self.handleData(frame: frame, then: then)
                case .headers:  self.handleHeader(frame: frame)
                default:        continue
                }
            }
        }
        HttpFrame.send(protobuf: data, flags: flags, stream: stream).write(to: task)
        return self
    }
}

public class StreamClient<T: ProtobufMessage>: GRPC<T> {

    let callback: ResponseHandler

    public init(url: String, callback: @escaping ResponseHandler) {
        self.callback = callback
        super.init(url: url)
    }

    @discardableResult
    public func with(data: ProtobufMessage, stream: UInt32, flags: HttpFlag = 0) -> Self {
        task.readData(ofMinLength: 0, maxLength: 1024, timeout: 0) { (data, isEOF, error) in
            let frames = HttpFrame.read(data)
            for frame in frames {
                switch frame.type {
                case .data:     self.handleData(frame: frame, then: self.callback)
                case .headers:  self.handleHeader(frame: frame)
                default:        continue
                }
            }
        }
        HttpFrame.send(protobuf: data, flags: flags, stream: stream).write(to: task)
        return self
    }
}
