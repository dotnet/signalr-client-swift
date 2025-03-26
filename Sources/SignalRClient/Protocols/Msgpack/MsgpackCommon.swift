// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation

// Messagepack protocol: https://github.com/msgpack/msgpack/blob/master/spec.md

// MARK: Public
// Predefined Timestamp Extension
public struct MsgpackTimestamp: Equatable {
    public var seconds: Int64
    public var nanoseconds: UInt32
}

// Those encoding extension methods are rarely used unless you want to encode to messagepack extension type
extension Encoder {
    public func isMsgpackEncoder() -> Bool {
        return self is MsgpackEncoder
    }

    // This method should be used with MsgpackEncoder otherwise it panics. Use isMsgpackEncoder to check.
    public func encodeMsgpackExt(extType: Int8, extData: Data) throws {
        let msgpackEncoder = self as! MsgpackEncoder
        try msgpackEncoder.encodeMsgpackExt(extType: extType, extData: extData)
    }
}

// Those decoding extension methods are rarely used unless you want to decode from messagepack extension type
extension Decoder {
    public func isMsgpackDecoder() -> Bool {
        return self is MsgpackDecoder
    }

    // This method should be used with MsgpackDecoder otherwise it panics. Use isMsgpackDecoder to check.
    public func getMsgpackExtType() throws -> Int8 {
        let msgpackDecoder = self as! MsgpackDecoder
        return try msgpackDecoder.getMsgpackExtType()
    }

    // This method should be used with MsgpackDecoder otherwise it panics. Use isMsgpackDecoder to check.
    public func getMsgpackExtData() throws -> Data {
        let msgpackDecoder = self as! MsgpackDecoder
        return try msgpackDecoder.getMsgpackExtData()
    }
}

// MARK: Internal
enum MsgpackElement: Equatable {
    case int(Int64)
    case uint(UInt64)
    case float32(Float32)
    case float64(Float64)
    case string(String)
    case bin(Data)
    case bool(Bool)
    case map([String: MsgpackElement])
    case array([MsgpackElement])
    case null
    case ext(Int8, Data)

    var typeDescription: String {
        switch self {
        case .bool:
            return "Bool"
        case .int, .uint:
            return "Integer"
        case .float32, .float64:
            return "Float"
        case .string:
            return "String"
        case .bin:
            return "Binary"
        case .map:
            return "Map"
        case .array:
            return "Array"
        case .null:
            return "Null"
        case .ext(let type, _):
            return "Extension(type:\(type))"
        }
    }
}

struct MsgpackCodingKey: CodingKey, Equatable {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init(intValue: Int) {
        self.intValue = intValue
        self.stringValue = String("Index \(intValue)")
    }
}
