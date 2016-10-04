//
//  SwiftGRPC/Sources/Http2.swift - HTTP/2 Library
//
//  This source file is part of the SwiftGRPC open source project
//  https://github.com/nathanborror/swift-grpc
//  Created by Nathan Borror on 10/1/16.
//

import Foundation
import hpack

// Streams

enum StreamState {
    case none
    case idle
    case reservedLocal
    case reservedRemote
    case open
    case halfClosedRemote
    case halfClosedLocal
    case closed
}

public typealias StreamID = Int
public struct StreamCache {
    
    var streams = [Int: StreamState]()
    var counter = 1
    
    public mutating func next() -> StreamID {
        streams[counter] = .none
        let s = counter
        counter += 2
        return s
    }
}

// Frames

public enum FrameType: UInt8 {
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
}

public typealias FrameFlag = UInt8
extension FrameFlag {
    public static let endStream: FrameFlag   = 1
    public static let settingsAck: FrameFlag = 1
    public static let pingAck: FrameFlag     = 1
    public static let endHeaders: FrameFlag  = 4
    public static let padded: FrameFlag      = 8
    public static let priority: FrameFlag    = 20
}

public struct Frame {
    public let type:    FrameType
    public let stream:  StreamID
    public let flags:   FrameFlag
    public let length:  Int
    public var payload: [UInt8]?
    
    public init(type: FrameType, stream: StreamID = 0, flags: FrameFlag = 0, length: Int = 0, payload: [UInt8]? = nil) {
        self.type = type
        self.stream = stream
        self.flags = flags
        self.length = length
        self.payload = payload
    }
    
    public init(headers: [(String, String)], stream: StreamID = 0, flags: FrameFlag = 0) {
        self.type = .headers
        self.stream = stream
        self.flags = flags
        
        let encoder = hpack.Encoder()
        let payload = encoder.encode(headers)
        
        self.payload = payload
        self.length = payload.count
    }
    
    public init(data: [UInt8], stream: StreamID = 0, flags: FrameFlag = 0) {
        self.type = .data
        self.stream = stream
        self.flags = flags
        self.payload = data
        self.length = data.count
    }
    
    public init?(bytes: [UInt8]) {
        guard bytes.count >= 9 else { return nil }
        let length = (UInt32(bytes[0]) << 16) + (UInt32(bytes[1]) << 8) + UInt32(bytes[2])
        self.length = Int(length)
        guard let type = FrameType(rawValue: bytes[3]) else {
            return nil
        }
        self.type = type
        self.flags = bytes[4]
        var stream = UInt32(bytes[5])
        stream <<= 8
        stream += UInt32(bytes[6])
        stream <<= 8
        stream += UInt32(bytes[7])
        stream <<= 8
        stream += UInt32(bytes[8])
        stream &= ~0x80000000
        self.stream = Int(stream)
        self.payload = nil
    }
    
    public func bytes() -> [UInt8] {
        var data = [UInt8]()
        
        let l = htonl(UInt32(self.length)) >> 8
        data.append(UInt8(l & 0xFF))
        data.append(UInt8((l >> 8) & 0xFF))
        data.append(UInt8((l >> 16) & 0xFF))
        
        data.append(self.type.rawValue)
        data.append(self.flags)
        
        let s = htonl(UInt32(self.stream))
        data.append(UInt8(s & 0xFF))
        data.append(UInt8((s >> 8) & 0xFF))
        data.append(UInt8((s >> 16) & 0xFF))
        data.append(UInt8((s >> 24) & 0xFF))
        return data
    }
}

// Client Delegate

public protocol Http2Delegate: class {
    func clientConnected(http: Http2)
    func client(http: Http2, hasFrame frame: Frame)
}

// Client

public class Http2: NSObject {
    
    private let url: URL
    
    public var delegate: Http2Delegate?
    
    var inputStream: InputStream?
    var outputStream: OutputStream?
    
    var isConnected = false
    var isConnecting = false
    var isReadyToWrite = false {
        didSet { if isReadyToWrite { writeHandshake() }}
    }
    
    private var inputQueue: [UInt8]
    private let writeQueue: OperationQueue
    private var fragBuffer: Data?
    
    private static let sharedQueue = DispatchQueue(label: "com.nathanborror.grpc.http2", attributes: [])
    
    public var streams: StreamCache
    
    public init(url: URL) {
        self.url = url
        self.writeQueue = OperationQueue()
        self.writeQueue.maxConcurrentOperationCount = 1
        self.inputQueue = []
        self.streams = StreamCache()
    }
    
    public func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        attemptConnection()
        isConnecting = false
    }
    
    func attemptConnection() {
        guard let req = makeRequest() else {
            print("HTTP/2 connection attempt failed")
            return
        }
        makeStreams(with: req)
    }
    
    func makeRequest() -> Data? {
        let req = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true).takeRetainedValue()
        
        CFHTTPMessageAppendBytes(req, prism, prism.count)
        
        // TODO: Figure out how to get rid of the above without having
        // CFHTTPMessageCopySerializedMessage returning nil.
        
        guard let cfData = CFHTTPMessageCopySerializedMessage(req) else {
            print("CFHTTPMessageCopySerializedMessage returned nil")
            return nil
        }
        return cfData.takeRetainedValue() as Data
    }
    
    func makeStreams(with request: Data) {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        guard let host = url.host,
            let port = url.port else { fatalError() }
        
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)
        
        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream!.takeRetainedValue()
        
        guard let input = inputStream,
            let output = outputStream else { fatalError() }
        
        input.delegate = self
        output.delegate = self
        
        CFReadStreamSetDispatchQueue(input, Http2.sharedQueue)
        CFWriteStreamSetDispatchQueue(output, Http2.sharedQueue)
        
        input.open()
        output.open()
    }
    
    func writeHandshake() {
        var out = [UInt8]()
        out += prism
        out += settings
        write(bytes: out)
        delegate?.clientConnected(http: self)
    }
    
    lazy var prism: [UInt8] = {
        return [UInt8]("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)
    }()
    
    lazy var settings: [UInt8] = {
        return Frame(type: .settings).bytes()
    }()
    
    func processInput() {
        guard let input = inputStream else { return }
        
        var buffer = [UInt8](repeating: 0, count: 4096)
        let read = input.read(&buffer, maxLength: buffer.count)
        inputQueue += Array(buffer[0..<read])
        
        dequeueInput()
    }
    
    func dequeueInput() {
        while !inputQueue.isEmpty {
            let buffer = Array(inputQueue[0..<9])
            inputQueue = Array(inputQueue[buffer.count..<inputQueue.count])
            guard var frame = Frame(bytes: buffer) else {
                return
            }
            
            if frame.length > 0 {
                let count = Int(frame.length)
                frame.payload = Array(inputQueue[0..<count])
                inputQueue = Array(inputQueue[count..<inputQueue.count])
            }
            
            delegate?.client(http: self, hasFrame: frame)
        }
    }
    
    public func disconnect() {
        writeQueue.cancelAllOperations()
        if let stream = inputStream {
            stream.close()
            CFReadStreamSetDispatchQueue(stream, nil)
            stream.delegate = nil
            inputStream = nil
        }
        if let stream = outputStream {
            stream.close()
            CFWriteStreamSetDispatchQueue(stream, nil)
            stream.delegate = nil
            outputStream = nil
        }
        isConnected = false
        isConnecting = false
    }
    
    public func write(frame: Frame) {
        var out = frame.bytes()
        if let payload = frame.payload {
            out += payload
        }
        write(bytes: out)
    }
    
    public func write(bytes: [UInt8]) {
        guard isReadyToWrite else { return }
        guard let output = outputStream else { fatalError() }
        output.write(bytes, maxLength: bytes.count)
    }
}

extension Http2: StreamDelegate {
    
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event.openCompleted:
            if aStream == outputStream {
                isConnected = true
                isReadyToWrite = true
            }
            break
            
        case Stream.Event.hasSpaceAvailable:
            break
            
        case Stream.Event.hasBytesAvailable:
            guard aStream == inputStream else { return }
            processInput()
            break
            
        case Stream.Event.endEncountered:
            disconnect()
            break
            
        case Stream.Event.errorOccurred:
            disconnect()
            break
            
        default:
            print("unknown", eventCode)
        }
    }
}

// Utils

let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
let htonl  = isLittleEndian ? _OSSwapInt32 : { $0 } // host-to-network-long
