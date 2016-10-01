//
//  SwiftGRPC/Sources/Http2.swift - HTTP/2 Library
//
//  This source file is part of the SwiftGRPC open source project
//  https://github.com/nathanborror/swift-grpc
//  Created by Nathan Borror on 10/1/16.
//

import Foundation

let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
let htonl  = isLittleEndian ? _OSSwapInt32 : { $0 } // host-to-network-long

public enum HttpFrameType: UInt8, CustomStringConvertible {
    case data           = 0
    case headers        = 1
    case priority       = 2
    case rstStream      = 3
    case settings       = 4
    case pushPromise    = 5
    case ping           = 6
    case goaway         = 7
    case windowUpdate   = 8
    case continuation   = 9

    public var description: String {
        switch self {
        case .data:         return "HTTP2_DATA"
        case .headers:      return "HTTP2_HEADERS"
        case .priority:     return "HTTP2_PRIORITY"
        case .rstStream:    return "HTTP2_RST_STREAM"
        case .settings:     return "HTTP2_SETTINGS"
        case .pushPromise:  return "HTTP2_PUSH_PROMISE"
        case .ping:         return "HTTP2_PING"
        case .goaway:       return "HTTP2_GOAWAY"
        case .windowUpdate: return "HTTP2_WINDOW_UPDATE"
        case .continuation: return "HTTP2_CONTINUATION"
        }
    }
}

public enum HttpSettings: UInt16 {
    case headerTableSize        = 1
    case enablePush             = 2
    case maxConcurrentStreams   = 3
    case initialWindowSize      = 4
    case maxFrameSize           = 5
    case maxHeaderListSize      = 6
}

public enum HttpStreamState {
    case none
    case idle
    case reservedLocal
    case reservedRemote
    case open
    case halfClosedRemote
    case halfClosedLocal
    case closed
}

public typealias HttpFlag = UInt8
extension HttpFlag {
    public static let endStream: HttpFlag   = 1
    public static let settingsAck: HttpFlag = 1
    public static let pingAck: HttpFlag     = 1
    public static let endHeaders: HttpFlag  = 4
    public static let padded: HttpFlag      = 8
    public static let priority: HttpFlag    = 20
}

public struct HttpFrame: CustomStringConvertible {
    let length:     UInt32
    let type:       HttpFrameType
    let flags:      HttpFlag
    let streamId:   UInt32

    var payload:    [UInt8]?

    var flagsStr: String {
        var s = ""
        if flags == 0 {
            s.append("NO FLAGS")
        }
        if (flags & HttpFlag.endStream) != 0 {
            s.append("+HTTP2_END_STREAM")
        }
        if (flags & HttpFlag.endHeaders) != 0 {
            s.append("+HTTP2_END_HEADERS")
        }
        return s
    }

    public var bytes: [UInt8] {
        var data = [UInt8]()

        let l = htonl(length) >> 8
        data.append(UInt8(l & 0xFF))
        data.append(UInt8((l >> 8) & 0xFF))
        data.append(UInt8((l >> 16) & 0xFF))

        data.append(type.rawValue)
        data.append(flags)

        let s = htonl(streamId)
        data.append(UInt8(s & 0xFF))
        data.append(UInt8((s >> 8) & 0xFF))
        data.append(UInt8((s >> 16) & 0xFF))
        data.append(UInt8((s >> 24) & 0xFF))
        return data
    }

    public var data: Data {
        let b = self.bytes
        return Data(bytes: b, count: b.count)
    }

    public var description: String {
        return "\(type)(length: \(length), flags: \(flags, flagsStr), stream: \(streamId), payload: \(payload?.count ?? 0) bytes)"
    }

    public func write(to task: URLSessionStreamTask) {
        let handler: (Error?) -> Void = {
            if $0 != nil { print($0) }
        }
        task.write(self.data, timeout: 0, completionHandler: handler)
        guard let payload = payload else { return }
        task.write(Data(bytes: payload, count: payload.count), timeout: 0, completionHandler: handler)
    }

    // Frame Factories

    public static func preface(task: URLSessionStreamTask) {
        let prefaceData = HttpRequest.preface.data(using: String.Encoding.ascii)!
        task.write(prefaceData, timeout: 0) {
            if $0 != nil { print($0) }
        }
    }

    public static func settings(flags: HttpFlag = 0, stream: UInt32 = 0) -> HttpFrame {
        return HttpFrame(length: 0, type: .settings, flags: flags, streamId: stream, payload: nil)
    }

    public static func windowUpdate(flags: HttpFlag = 0, stream: UInt32 = 0) -> HttpFrame {
        let windowData = Bytes()
        windowData.import32Bits(from: UInt32(983025))
        return HttpFrame(length: UInt32(windowData.data.count), type: .windowUpdate, flags: flags, streamId: stream, payload: windowData.data)
    }

    public static func send(headers: [(String, String)], flags: HttpFlag = 0, stream: UInt32 = 0) -> HttpFrame {
        let bytes = HttpRequest.set(headers: headers)
        return HttpFrame(length: UInt32(bytes.count), type: .headers, flags: flags, streamId: stream, payload: bytes)
    }

    public static func send(bytes: [UInt8], flags: HttpFlag = 0, stream: UInt32 = 0) -> HttpFrame {
        var out: [UInt8] = [0, 0, 0, 0] // TODO: Do these need to be set?
        do {
            out += [UInt8(bytes.count)]
            out += bytes
        } catch {
            fatalError("\(error)")
        }
        return HttpFrame(length: UInt32(bytes.count), type: .data, flags: flags, streamId: stream, payload: out)
    }

    // Read

    public static func read(_ data: Data?) -> [HttpFrame] {
        guard let data = data else { return [] }
        var frames = [HttpFrame]()
        var bytes = [UInt8](data)
        while bytes.count > 0 {
            let (frame, remaining) = HttpResponse.process(bytes: bytes)
            frames.append(frame)
            bytes = remaining
        }
        return frames
    }
}

class HttpHeaderDecoder: HeaderListener {

    var headers = [(String, String, Bool)]()

    func addHeader(name: [UInt8], value: [UInt8], sensitive: Bool) {
        let nameStr = String(bytes: name, encoding: .utf8)!
        let valueStr = String(bytes: value, encoding: .utf8)!
        headers.append((nameStr, valueStr, sensitive))
    }
}

public struct HttpRequest {

    static let preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

    public static func set(headers: [(String, String)]) -> [UInt8] {
        let bytes = Bytes()
        let encoder = HPACKEncoder()
        do {
            for (name, value) in headers {
                try encoder.encodeHeader(out: bytes, name: name, value: value)
            }
        } catch {
            print(error)
        }
        return bytes.data
    }
}

public struct HttpResponse {

    public static func parse(bytes b: [UInt8]) -> HttpFrame {
        let length = (UInt32(b[0]) << 16) + (UInt32(b[1]) << 8) + UInt32(b[2])
        let type = HttpFrameType(rawValue: b[3])!
        let flags = b[4]
        var sid: UInt32 = UInt32(b[5])
        sid <<= 8
        sid += UInt32(b[6])
        sid <<= 8
        sid += UInt32(b[7])
        sid <<= 8
        sid += UInt32(b[8])
        sid &= ~0x80000000
        return HttpFrame(length: length, type: type, flags: flags, streamId: sid, payload: nil)
    }

    public static func process(bytes b: [UInt8]) -> (HttpFrame, [UInt8]) {
        var frame = HttpResponse.parse(bytes: b)
        if frame.length > 0 {
            let len = 9 + Int(frame.length)
            frame.payload = Array(b[9..<len])
        }
        let offset = 9 + (frame.payload?.count ?? 0)
        let bytes = Array(b[offset..<b.count])
        return (frame, bytes)
    }
}

public struct HttpStream {

    var streams = [UInt32: HttpStreamState]()
    var counter = UInt32(1)

    public mutating func new() -> UInt32 {
        streams[counter] = .none
        let s = counter
        counter += 2
        return s
    }
}
