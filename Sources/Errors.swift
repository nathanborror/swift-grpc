//
//  SwiftGRPC/Sources/Errors.swift - GRPC Client
//
//  This source file is part of the SwiftGRPC open source project
//  https://github.com/nathanborror/swift-grpc
//  Created by Nathan Borror on 10/24/16.
//

import Foundation

public enum ResponseError: Error {
    case canceled(String)
    case unknown(String)
    case invalidArgument(String)
    case deadlineExceeded(String)
    case notFound(String)
    case alreadyExists(String)
    case permissionDenied(String)
    case unauthenticated(String)
    case resourceExhausted(String)
    case failedPrecondition(String)
    case aborted(String)
    case outOfRange(String)
    case unimplemented(String)
    case `internal`(String)
    case unavailable(String)
    case dataLoss(String)
    
    init?(code: Int, message: String) {
        switch code {
        case 1:  self = .canceled(message)
        case 2:  self = .unknown(message)
        case 3:  self = .invalidArgument(message)
        case 4:  self = .deadlineExceeded(message)
        case 5:  self = .notFound(message)
        case 6:  self = .alreadyExists(message)
        case 7:  self = .permissionDenied(message)
        case 16: self = .unauthenticated(message)
        case 8:  self = .resourceExhausted(message)
        case 9:  self = .failedPrecondition(message)
        case 10: self = .aborted(message)
        case 11: self = .outOfRange(message)
        case 12: self = .unimplemented(message)
        case 13: self = .internal(message)
        case 14: self = .unavailable(message)
        case 15: self = .dataLoss(message)
        default: return nil
        }
    }
}
