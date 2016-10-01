import Foundation
import Protobuf

public class GRPCClient<T: ProtobufMessage> {

    public typealias Callback = (T?, Error?) -> Void

    let session: URLSession
    let scheme: String
    let host: String
    let port: Int

    var task: URLSessionStreamTask?
    var stream: UInt32?
    var method: String = "POST"

    private var streams: HttpStream
    private var streamCallbacks = [UInt32: Callback?]()
    private var streamCallback: Callback?

    private let timeout: TimeInterval = 0
    private let minReadLength: Int = 0
    private let maxReadLength: Int = 1024

    public init(url: String) {
        guard let url = URL(string: url) else { fatalError() }
        self.session = URLSession(configuration: .default)
        self.streams = HttpStream()
        self.host = url.host ?? ""
        self.port = url.port ?? 80
        self.scheme = url.scheme ?? "http"
        self.task = session.streamTask(withHostName: host, port: port)
    }

    public convenience init(url: String, streamTo callback: @escaping Callback) {
        self.init(url: url)
        streamCallback = callback
    }

    public func get(_ path: String, flags: HttpFlag = 0) -> GRPCClient {
        method = "GET"
        return call(path, flags: flags)
    }

    public func post(_ path: String, flags: HttpFlag = 0) -> GRPCClient {
        method = "POST"
        return call(path, flags: flags)
    }

    @discardableResult
    public func call(_ path: String, flags: HttpFlag = 0) -> GRPCClient {
        stream = newStream()

        guard let task = task, let stream = stream else { return self }
        if task.state != .running {
            start()
        }

        let headers = [
            (":method", method),
            (":scheme", scheme),
            (":path", path),
            (":authority", host),
            ("content-type", "application/grpc+proto"),
            ("user-agent", "grpc-swift/1.0"),
            ("te", "trailers"),
        ]
        HttpFrame.header(task: task, headers: headers, flags: flags, stream: stream)
        return self
    }

    @discardableResult
    public func data(_ data: ProtobufMessage, flags: HttpFlag = 0, callback: Callback? = nil) -> GRPCClient {
        guard let task = task, let stream = stream else { return self }

        streamCallbacks[stream] = (streamCallback != nil) ? streamCallback : callback

        task.readData(ofMinLength: 0, maxLength: 1024, timeout: 0) { (data, isEOF, error) in
            self.completion(data: data, isEOF: isEOF, error: error)
        }
        HttpFrame.data(task: task, protobuf: data, flags: flags, stream: stream)
        return self
    }

    private func completion(data: Data?, isEOF: Bool, error: Error?) {
        let frames = HttpFrame.read(data)
        for frame in frames {
            switch frame.type {
            case .data:
                guard let callback = streamCallbacks[frame.streamId] else { return }
                let b = Array(frame.payload![5..<frame.payload!.count])
                let data = Data(bytes: b, count: b.count)
                do {
                    let out = try T(protobuf: data)
                    callback?(out, nil)
                } catch { callback?(nil, error) }
            default: break
            }
        }
    }

    private func newStream() -> UInt32 {
        let streamId = streams.new()
        streams.streams[streamId] = .idle
        return streamId
    }

    private func start() {
        guard let task = task else { return }
        task.resume()
        HttpFrame.preface(task: task)
        HttpFrame.settings(task: task, flags: .settingsAck)
    }

    private func close() {
        task?.closeWrite()
    }
}
