import Foundation

// MARK: Swift Decodable implementation. Decoder, KeyedContainer, UnkeyedContainer, SingleValueContainer
class MsgpackDecoder: Decoder, MsgpackElementLoader {
    var codingPath: [any CodingKey]
    var messagepackType: MsgpackElement?
    var userInfo: [CodingUserInfoKey: Any]

    init(
        codingPath: [any CodingKey] = [],
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) {
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func getMsgpackExtType() throws -> Int8 {
        guard let msgpackElement = self.messagepackType else {
            throw MsgpackDecodingError.decoderNotInitialized
        }
        guard case let MsgpackElement.ext(extType, _) = msgpackElement else {
            throw DecodingError.typeMismatch(
                Decoder.self,
                .init(
                    codingPath: codingPath,
                    debugDescription:
                        "\(msgpackElement.typeDescription) is not extension type"))
        }
        return extType
    }

    func getMsgpackExtData() throws -> Data {
        guard let msgpackElement = self.messagepackType else {
            throw MsgpackDecodingError.decoderNotInitialized
        }
        guard case let MsgpackElement.ext(_, data) = msgpackElement else {
            throw DecodingError.typeMismatch(
                Decoder.self,
                .init(
                    codingPath: codingPath,
                    debugDescription:
                        "\(msgpackElement.typeDescription) is not extension type"))
        }
        return data
    }

    func loadMsgpackElement(from data: MsgpackElement) throws {
        messagepackType = data
    }

    func container<Key>(keyedBy type: Key.Type) throws
        -> KeyedDecodingContainer<Key> where Key: CodingKey
    {
        guard let messagepackType = messagepackType else {
            throw MsgpackDecodingError.decoderNotInitialized
        }
        let container = try MsgpackKeyedDecodingContainer<Key>(
            codingPath: codingPath, userInfo: userInfo,
            msgpackValue: messagepackType)
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard let messagepackType = messagepackType else {
            throw MsgpackDecodingError.decoderNotInitialized
        }
        let container = try MsgpackUnkeyedDecodingContainer(
            codingPath: codingPath, userInfo: userInfo,
            msgpackValue: messagepackType)
        return container
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        guard let messagepackType = messagepackType else {
            throw MsgpackDecodingError.decoderNotInitialized
        }
        let container = try MsgpackSingleValueDecodingContainer(
            codingPath: codingPath, userInfo: userInfo,
            msgpackValue: messagepackType)
        return container
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let (msgpackElement, remaining) = try MsgpackElement.parse(data: data)
        if !remaining.isEmpty {
            throw MsgpackDecodingError.corruptMessage
        }
        try loadMsgpackElement(from: msgpackElement)
        let result = try msgpackElement.decode(type: type, codingPath: codingPath)
        guard let result = result else {
            return try type.init(from: self)
        }
        return result
    }
}

class MsgpackKeyedDecodingContainer<Key: CodingKey>:
    KeyedDecodingContainerProtocol, MsgpackElementLoader
{
    private var holder: [String: MsgpackElement] = [:]
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any]

    init(
        codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any],
        msgpackValue: MsgpackElement
    ) throws {
        self.codingPath = codingPath
        self.userInfo = userInfo
        try loadMsgpackElement(from: msgpackValue)
    }

    func loadMsgpackElement(from data: MsgpackElement) throws {
        switch data {
        case .map(let m):
            self.holder = m
        default:
            throw DecodingError.typeMismatch(
                [String: Any].self,
                .init(
                    codingPath: codingPath,
                    debugDescription:
                        "Expected to decode \([String:Any].self) but found \(data.typeDescription) instead."
                ))

        }
    }

    var allKeys: [Key] { holder.keys.compactMap { k in Key(stringValue: k) } }

    func contains(_ key: Key) -> Bool {
        return holder[key.stringValue] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        let v = try getMsgpackElement(key)
        return v.isNil()
    }

    func decode<T>(_ value: T.Type, forKey key: Key) throws -> T
    where T: Decodable {
        let v = try getMsgpackElement(key)
        let result = try v.decode(
            type: value, codingPath: subCodingPath(key: key))
        guard let result = result else {
            let decoder = try initDecoder(key: key, value: v)
            return try T.init(from: decoder)
        }
        return result
    }

    func nestedContainer<NestedKey>(
        keyedBy keyType: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        let v = try getMsgpackElement(key)
        let decoder = try initDecoder(key: key, value: v)
        let container = try decoder.container(keyedBy: keyType)
        return container
    }

    func nestedUnkeyedContainer(forKey key: Key) throws
        -> any UnkeyedDecodingContainer
    {
        let v = try getMsgpackElement(key)
        let decoder = try initDecoder(key: key, value: v)
        let container = try decoder.unkeyedContainer()
        return container
    }

    func superDecoder() throws -> any Decoder {
        let key = MsgpackCodingKey(stringValue: "super")
        let v = try getMsgpackElement(key)
        let decoder = try initDecoder(key: key, value: v)
        return decoder
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        let v = try getMsgpackElement(key)
        let decoder = try initDecoder(key: key, value: v)
        return decoder
    }

    private func getMsgpackElement(_ key: CodingKey) throws -> MsgpackElement {
        let v = holder[key.stringValue]
        guard let v = v else {
            throw DecodingError.keyNotFound(
                key,
                .init(
                    codingPath: subCodingPath(key: key),
                    debugDescription: "No value associated with key \(key)."))
        }
        return v
    }

    private func initDecoder(key: CodingKey, value: MsgpackElement) throws
        -> MsgpackDecoder
    {
        let decoder = MsgpackDecoder(
            codingPath: subCodingPath(key: key), userInfo: self.userInfo)
        try decoder.loadMsgpackElement(from: value)
        return decoder
    }

    private func subCodingPath(key: CodingKey) -> [CodingKey] {
        var codingPath = self.codingPath
        codingPath.append(key)
        return codingPath
    }

}

class MsgpackUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    private var holder: [MsgpackElement] = []
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any]

    var count: Int? { holder.count }
    var isAtEnd: Bool { currentIndex >= holder.count }
    var currentIndex: Int

    init(
        codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any],
        msgpackValue: MsgpackElement
    ) throws {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.currentIndex = 0
        try loadMsgpackElement(from: msgpackValue)
    }

    func loadMsgpackElement(from data: MsgpackElement) throws {
        switch data {
        case .array(let m):
            self.holder = m
        default:
            throw DecodingError.typeMismatch(
                [Any].self,
                .init(
                    codingPath: codingPath,
                    debugDescription:
                        "Expected to decode \([Any].self) but found \(data.typeDescription) instead."
                ))
        }
    }

    func decodeNil() throws -> Bool {
        let msgpackElement = try getMsgpackElement(Never.self)
        let isNil = msgpackElement.isNil()
        currentIndex += isNil ? 1 : 0
        return isNil
    }

    func decode<T>(_ value: T.Type) throws -> T where T: Decodable {
        let msgpackElement = try getMsgpackElement(T.self)
        guard
            let result = try msgpackElement.decode(
                type: value, codingPath: subCodingPath())
        else {
            let decoder = try initDecoder(value: msgpackElement)
            currentIndex += 1
            return try value.init(from: decoder)
        }
        currentIndex += 1
        return result
    }

    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) throws
        -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
    {
        let msgpackElement = try getMsgpackElement(
            KeyedDecodingContainer<NestedKey>.self)
        let decoder = try initDecoder(value: msgpackElement)
        currentIndex += 1
        return try decoder.container(keyedBy: keyType)
    }

    func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let msgpackElement = try getMsgpackElement(UnkeyedDecodingContainer.self)
        let decoder = try initDecoder(value: msgpackElement)
        currentIndex += 1
        return try decoder.unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        let msgpackElement = try getMsgpackElement(Decoder.self)
        let decoder = try initDecoder(value: msgpackElement)
        currentIndex += 1
        return decoder
    }

    private func getMsgpackElement(_ targetType: Any.Type) throws -> MsgpackElement {
        guard currentIndex < holder.count else {
            throw DecodingError.valueNotFound(
                targetType,
                .init(
                    codingPath: subCodingPath(),
                    debugDescription: "Unkeyed container is at end."))
        }
        return holder[currentIndex]
    }

    private func initDecoder(value: MsgpackElement) throws -> MsgpackDecoder {
        let decoder = MsgpackDecoder(
            codingPath: subCodingPath(), userInfo: self.userInfo)
        try decoder.loadMsgpackElement(from: value)
        return decoder
    }

    private func subCodingPath() -> [CodingKey] {
        var codingPath = self.codingPath
        codingPath.append(MsgpackCodingKey(intValue: currentIndex))
        return codingPath
    }
}

class MsgpackSingleValueDecodingContainer: SingleValueDecodingContainer,
    MsgpackElementLoader
{
    private var holder: MsgpackElement = .null
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any]

    init(
        codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any],
        msgpackValue: MsgpackElement
    ) throws {
        self.codingPath = codingPath
        self.userInfo = userInfo
        try loadMsgpackElement(from: msgpackValue)
    }

    func loadMsgpackElement(from data: MsgpackElement) throws {
        self.holder = data
    }

    func decodeNil() -> Bool {
        return holder.isNil()
    }

    func decode<T>(_ value: T.Type) throws -> T where T: Decodable {
        guard
            let result = try holder.decode(type: value, codingPath: codingPath)
        else {
            let decoder = try initDecoder(value: holder)
            return try value.init(from: decoder)
        }
        return result
    }

    private func initDecoder(value: MsgpackElement) throws -> MsgpackDecoder {
        let decoder = MsgpackDecoder(
            codingPath: codingPath, userInfo: self.userInfo)
        try decoder.loadMsgpackElement(from: value)
        return decoder
    }
}

private protocol MsgpackElementLoader {
    func loadMsgpackElement(from data: MsgpackElement) throws
}

// MARK: (Decoding Part) Intermediate type which implements messagepack protocol. Similar to JSonObject
extension MsgpackElement {
    // MARK: Convert from Data to MsgpackElement
    static func parse(data: Data) throws -> (MsgpackElement, Data) {
        try assertLength(data: data, length: 1)
        let first = data[0]
        if first <= 0x7f || first >= 0xe0 || (first >= 0xcc && first <= 0xd3) {
            return try parseNumber(data: data)
        }
        if (first >= 0xa0 && first <= 0xbf) || (first >= 0xd9 && first <= 0xdb)
        {
            return try parseString(data: data)
        }
        if (first >= 0x80 && first <= 0x8f) || (first >= 0xde && first <= 0xdf)
        {
            return try parseMap(data: data)
        }
        if (first >= 0x90 && first <= 0x9f) || (first >= 0xdc && first <= 0xdd)
        {
            return try parseArray(data: data)
        }
        if first >= 0xc4 && first <= 0xc6 {
            return try parseBinary(data: data)
        }
        if first >= 0xd4 && first <= 0xde || first >= 0xc7 && first <= 0xc9 {
            return try parseExtension(data: data)
        }
        switch first {
        case 0xca:
            return try parseFloat32(data: data.subdata(in: 1..<data.count))
        case 0xcb:
            return try parseFloat64(data: data.subdata(in: 1..<data.count))
        case 0xc2:
            return (MsgpackElement.bool(false), data.subdata(in: 1..<data.count))
        case 0xc3:
            return (MsgpackElement.bool(true), data.subdata(in: 1..<data.count))
        case 0xc0:
            return (MsgpackElement.null, data.subdata(in: 1..<data.count))
        default:
            throw MsgpackDecodingError.decdoeWithUnexpectedMsgpackElement(first)
        }
    }

    private static func parseNumber(data: Data) throws -> (MsgpackElement, Data) {
        try assertLength(data: data, length: 1)
        let first = data[0]
        let remaining = data.subdata(in: 1..<data.count)
        // Fixed positive int
        if first >= 0x00 && first <= 0x7f {
            let uint8 = UInt8(first)
            return (MsgpackElement.uint(UInt64(uint8)), remaining)
        }
        // Fixed negative int
        if first >= 0xe0 && first <= 0xff {
            let int8Data = data[..<1]
            let int8: Int8 = int8Data.withUnsafeBytes { pointer in
                return pointer.load(as: Int8.self)
            }
            return (MsgpackElement.int(Int64(int8)), remaining)
        }

        switch first {
        case 0xcc: // UInt8
            let (uint8, remaining) = try parseRawUInt8(data: remaining)
            return (MsgpackElement.uint(UInt64(uint8)), remaining)
        case 0xcd: // UInt16
            let (uint16, remaining) = try parseRawUInt16(data: remaining)
            return (MsgpackElement.uint(UInt64(uint16)), remaining)
        case 0xce: // UInt32
            let (uint32, remaining) = try parseRawUInt32(data: remaining)
            return (MsgpackElement.uint(UInt64(uint32)), remaining)
        case 0xcf: // UInt64
            let (uint64, remaining) = try parseRawUInt64(data: remaining)
            return (MsgpackElement.uint(uint64), remaining)
        case 0xd0: //Int8
            let (int8, remaining) = try parseRawInt8(data: remaining)
            return (MsgpackElement.int(Int64(int8)), remaining)
        case 0xd1: //Int16
            let (int16, remaining) = try parseRawInt16(data: remaining)
            return (MsgpackElement.int(Int64(int16)), remaining)
        case 0xd2: //Int32
            let (int32, remaining) = try parseRawInt32(data: remaining)
            return (MsgpackElement.int(Int64(int32)), remaining)
        case 0xd3: //Int64
            let (int64, remaining) = try parseRawInt64(data: remaining)
            return (MsgpackElement.int(int64), remaining)
        default:
            throw MsgpackDecodingError.decdoeWithUnexpectedMsgpackElement(first)
        }
    }

    private static func parseFloat32(data: Data) throws -> (MsgpackElement, Data) {
        // float32 memory edianness is undefined. Use uint32 bits to init.
        let (uint32, remaining) = try parseRawUInt32(data: data)
        let float32 = Float32(bitPattern: uint32)
        return (MsgpackElement.float32(float32), remaining)
    }

    private static func parseFloat64(data: Data) throws -> (MsgpackElement, Data) {
        // float64 memory edianness is undefined. Use uint64 bits to init.
        let (uint64, remaining) = try parseRawUInt64(data: data)
        let float64 = Float64(bitPattern: uint64)
        return (MsgpackElement.float64(float64), remaining)
    }

    private static func parseString(data: Data) throws -> (MsgpackElement, Data) {
        try assertLength(data: data, length: 1)
        var length: Int = 0
        let first = data[0]
        var remaining = data.subdata(in: 1..<data.count)
        if first >= 0xa0 && first <= 0xbf {
            length = Int(first & 0x1f)
        } else {
            switch first {
            case 0xd9: //Str8
                var uint8: UInt8
                (uint8, remaining) = try parseRawUInt8(data: remaining)
                length = Int(uint8)
            case 0xda: //str16
                var uint16: UInt16
                (uint16, remaining) = try parseRawUInt16(data: remaining)
                length = Int(uint16)
            case 0xdb: //str32
                var uint32: UInt32
                (uint32, remaining) = try parseRawUInt32(data: remaining)
                guard uint32 <= Int.max else {
                    throw MsgpackDecodingError.decodeStringTooLarge(uint32)
                }
                length = Int(uint32)
            default:
                throw MsgpackDecodingError.decdoeWithUnexpectedMsgpackElement(
                    first)
            }
        }
        try assertLength(data: remaining, length: length)
        guard let str = String(data: remaining[..<length], encoding: .utf8)
        else {
            throw MsgpackDecodingError.decodeStringError
        }
        return (
            MsgpackElement.string(str),
            remaining.subdata(in: length..<remaining.count)
        )
    }

    private static func parseBinary(data: Data) throws -> (MsgpackElement, Data) {
        try assertLength(data: data, length: 1)
        var length: Int = 0
        let first = data[0]
        var remaining = data.subdata(in: 1..<data.count)
        switch first {
        case 0xc4: //bin8
            var uint8: UInt8
            (uint8, remaining) = try parseRawUInt8(data: remaining)
            length = Int(uint8)
        case 0xc5: //bin16
            var uint16: UInt16
            (uint16, remaining) = try parseRawUInt16(data: remaining)
            length = Int(uint16)
        case 0xc6: //bin32
            var uint32: UInt32
            (uint32, remaining) = try parseRawUInt32(data: remaining)
            guard uint32 <= Int.max else {
                throw MsgpackDecodingError.decodeBinaryTooLarge(uint32)
            }
            length = Int(uint32)
        default:
            throw MsgpackDecodingError.decdoeWithUnexpectedMsgpackElement(first)
        }
        try assertLength(data: remaining, length: length)
        let binary = remaining.subdata(in: 0..<length)
        return (
            MsgpackElement.bin(binary),
            remaining.subdata(in: length..<remaining.count)
        )
    }

    private static func parseMap(data: Data) throws -> (MsgpackElement, Data) {
        try assertLength(data: data, length: 1)
        var length: Int = 0
        let first = data[0]
        var remaining = data.subdata(in: 1..<data.count)
        if first >= 0x80 && first <= 0x8f {
            length = Int(first & 0x0f)
        } else {
            switch first {
            case 0xde: //map16
                var uint16: UInt16
                (uint16, remaining) = try parseRawUInt16(data: remaining)
                length = Int(uint16)
            case 0xdf: //map32
                var uint32: UInt32
                (uint32, remaining) = try parseRawUInt32(data: remaining)
                guard uint32 <= Int.max else {
                    throw MsgpackDecodingError.decodeMapTooLarge(uint32)
                }
                length = Int(uint32)
            default:
                throw MsgpackDecodingError.decdoeWithUnexpectedMsgpackElement(
                    first)
            }
        }

        var map: [String: MsgpackElement] = [:]
        for _ in 0..<length {
            var wrappedKey: MsgpackElement
            (wrappedKey, remaining) = try parseString(data: remaining)
            guard case .string(let key) = wrappedKey else {
                throw MsgpackDecodingError.decodeMapKeyNotString
            }
            var value: MsgpackElement
            (value, remaining) = try parse(data: remaining)
            map[key] = value
        }
        return (MsgpackElement.map(map), remaining)
    }

    private static func parseArray(data: Data) throws -> (MsgpackElement, Data) {
        try assertLength(data: data, length: 1)
        var length: Int = 0
        let first = data[0]
        var remaining = data.subdata(in: 1..<data.count)
        if first >= 0x90 && first <= 0x9f {
            length = Int(first & 0x0f)
        } else {
            switch first {
            case 0xdc: //array16
                var uint16: UInt16
                (uint16, remaining) = try parseRawUInt16(data: remaining)
                length = Int(uint16)
            case 0xdd: //array32
                var uint32: UInt32
                (uint32, remaining) = try parseRawUInt32(data: remaining)
                guard uint32 <= Int.max else {
                    throw MsgpackDecodingError.decodeArrayTooLarge(uint32)
                }
                length = Int(uint32)
            default:
                throw MsgpackDecodingError.decdoeWithUnexpectedMsgpackElement(
                    first)
            }
        }

        var array: [MsgpackElement] = []
        array.reserveCapacity(length)
        for _ in 0..<length {
            var value: MsgpackElement
            (value, remaining) = try parse(data: remaining)
            array.append(value)
        }
        return (MsgpackElement.array(array), remaining)
    }

    private static func parseExtension(data: Data) throws -> (MsgpackElement, Data)
    {
        try assertLength(data: data, length: 1)
        let first = data[0]
        var remaining = data.subdata(in: 1..<data.count)
        var extType: Int8
        var extLength: Int
        switch first {
        case 0xd4:
            extLength = 1
        case 0xd5:
            extLength = 2
        case 0xd6:
            extLength = 4
        case 0xd7:
            extLength = 8
        case 0xd8:
            extLength = 16
        case 0xc7:
            var uint8: UInt8
            (uint8, remaining) = try Self.parseRawUInt8(data: remaining)
            extLength = Int(uint8)
        case 0xc8:
            var uint16: UInt16
            (uint16, remaining) = try Self.parseRawUInt16(data: remaining)
            extLength = Int(uint16)
        case 0xc9:
            var uint32: UInt32
            (uint32, remaining) = try Self.parseRawUInt32(data: remaining)
            guard UInt64(uint32) <= UInt64(Int.max) else {
                throw MsgpackDecodingError.decodeExtensionTooLarge(uint32)
            }
            extLength = Int(uint32)
        default:
            throw MsgpackDecodingError.decdoeWithUnexpectedMsgpackElement(first)
        }

        (extType, remaining) = try Self.parseRawInt8(data: remaining)
        try assertLength(data: remaining, length: extLength)
        let extData = remaining.subdata(in: 0..<extLength)
        remaining = remaining.subdata(in: extLength..<remaining.count)

        return (MsgpackElement.ext(extType, extData), remaining)
    }

    fileprivate static func assertLength(data: Data, length: Int) throws {
        guard data.count >= length else {
            throw MsgpackDecodingError.corruptMessage
        }
    }

    // MARK: Convert from MsgpackElement to basic Swift type
    func decode<T>(type: T.Type, codingPath: [CodingKey] = []) throws -> T?
    where T: Decodable {
        do {
            switch type {
            case is UInt.Type:
                return try UInt(getUInt(max: UInt64(UInt.max))) as? T
            case is UInt8.Type:
                return try UInt8(getUInt(max: UInt64(UInt8.max))) as? T
            case is UInt16.Type:
                return try UInt16(getUInt(max: UInt64(UInt16.max))) as? T
            case is UInt32.Type:
                return try UInt32(getUInt(max: UInt64(UInt32.max))) as? T
            case is UInt64.Type:
                return try getUInt(max: UInt64.max) as? T

            // Signed integers
            case is Int.Type:
                return try Int(getInt(min: Int64(Int.min), max: Int64(Int.max)))
                    as? T
            case is Int8.Type:
                return try Int8(
                    getInt(min: Int64(Int8.min), max: Int64(Int8.max))) as? T
            case is Int16.Type:
                return try Int16(
                    getInt(min: Int64(Int16.min), max: Int64(Int16.max))) as? T
            case is Int32.Type:
                return try Int32(
                    getInt(min: Int64(Int32.min), max: Int64(Int32.max))) as? T
            case is Int64.Type:
                return try getInt(min: Int64.min, max: Int64.max) as? T

            // Float (Float16's decodable is implemented as Float32)
            case is Float32.Type:
                return Float32(try getFloat()) as? T
            case is Float64.Type:
                return try getFloat() as? T

            // Bool
            case is Bool.Type:
                guard case let .bool(bool) = self else {
                    throw MsgpackDecodingError.decodeTypeNotMatch
                }
                return bool as? T
            // Data
            case is Data.Type:
                guard case let .bin(data) = self else {
                    throw MsgpackDecodingError.decodeTypeNotMatch
                }
                return data as? T
            // String
            case is String.Type:
                guard case let .string(string) = self else {
                    throw MsgpackDecodingError.decodeTypeNotMatch
                }
                return string as? T
            default:
                return nil
            }
        } catch MsgpackDecodingError.decodeNumberWithInvalideRange(let number) {
            throw DecodingError.typeMismatch(
                T.self,
                .init(
                    codingPath: codingPath,
                    debugDescription: "Can't convert \(number) to \(T.self)"))
        } catch MsgpackDecodingError.decodeTypeNotMatch {
            throw DecodingError.typeMismatch(
                T.self,
                .init(
                    codingPath: codingPath,
                    debugDescription:
                        "Can't convert \(self.typeDescription) to \(T.self)"))
        }
    }

    func getUInt(max: UInt64) throws -> UInt64 {
        switch self {
        case let .uint(uint64):
            guard uint64 <= max else {
                throw MsgpackDecodingError.decodeNumberWithInvalideRange(
                    "\(uint64)")
            }
            return uint64
        case let .int(int64):
            guard int64 >= 0 && int64 <= max else {
                throw MsgpackDecodingError.decodeNumberWithInvalideRange(
                    "\(int64)")
            }
            return UInt64(int64)
        default:
            throw MsgpackDecodingError.decodeTypeNotMatch
        }
    }

    func getInt(min: Int64, max: Int64) throws -> Int64 {
        switch self {
        case let .uint(uint64):
            guard uint64 <= max else {
                throw MsgpackDecodingError.decodeNumberWithInvalideRange(
                    "\(uint64)")
            }
            return Int64(uint64)
        case let .int(int64):
            guard int64 >= min && int64 <= max else {
                throw MsgpackDecodingError.decodeNumberWithInvalideRange(
                    "\(int64)")
            }
            return Int64(int64)
        default:
            throw MsgpackDecodingError.decodeTypeNotMatch
        }
    }

    func getFloat() throws -> Float64 {
        switch self {
        case let .float32(float32):
            return Float64(float32)
        case let .float64(Float64):
            return Float64
        default:
            throw MsgpackDecodingError.decodeTypeNotMatch
        }
    }

    fileprivate func isNil() -> Bool {
        switch self {
        case .null:
            return true
        default:
            return false
        }
    }

    // Utils methods
    fileprivate static func parseRawUInt8(data: Data) throws -> (UInt8, Data) {
        try MsgpackElement.assertLength(data: data, length: 1)
        let uint8Data = data[..<1]
        let uint8 = uint8Data.withUnsafeBytes { pointer in
            return pointer.load(as: UInt8.self)
        }
        let remaining = data.subdata(in: 1..<data.count)
        return (uint8, remaining)
    }

    fileprivate static func parseRawUInt16(data: Data) throws -> (UInt16, Data)
    {
        try MsgpackElement.assertLength(data: data, length: 2)
        let uint16Data = data[..<2]
        let uint16 = uint16Data.withUnsafeBytes { pointer in
            return pointer.load(as: UInt16.self)
        }.bigEndian
        let remaining = data.subdata(in: 2..<data.count)
        return (uint16, remaining)
    }

    fileprivate static func parseRawUInt32(data: Data) throws -> (UInt32, Data)
    {
        try MsgpackElement.assertLength(data: data, length: 4)
        let uint32Data = data[..<4]
        let uint32 = uint32Data.withUnsafeBytes { pointer in
            return pointer.load(as: UInt32.self)
        }.bigEndian
        let remaining = data.subdata(in: 4..<data.count)
        return (uint32, remaining)
    }

    fileprivate static func parseRawUInt64(data: Data) throws -> (UInt64, Data)
    {
        try MsgpackElement.assertLength(data: data, length: 8)
        let uint64Data = data[..<8]
        let uint64 = uint64Data.withUnsafeBytes { pointer in
            return pointer.load(as: UInt64.self)
        }.bigEndian
        let remaining = data.subdata(in: 8..<data.count)
        return (uint64, remaining)
    }

    fileprivate static func parseRawInt8(data: Data) throws -> (Int8, Data) {
        try MsgpackElement.assertLength(data: data, length: 1)
        let int8Data = data[..<1]
        let int8 = int8Data.withUnsafeBytes { pointer in
            return pointer.load(as: Int8.self)
        }.bigEndian
        let remaining = data.subdata(in: 1..<data.count)
        return (int8, remaining)
    }

    fileprivate static func parseRawInt16(data: Data) throws -> (Int16, Data) {
        try MsgpackElement.assertLength(data: data, length: 2)
        let int16Data = data[..<2]
        let int16 = int16Data.withUnsafeBytes { pointer in
            return pointer.load(as: Int16.self)
        }.bigEndian
        let remaining = data.subdata(in: 2..<data.count)
        return (int16, remaining)
    }

    fileprivate static func parseRawInt32(data: Data) throws -> (Int32, Data) {
        try MsgpackElement.assertLength(data: data, length: 4)
        let int32Data = data[..<4]
        let int32 = int32Data.withUnsafeBytes { pointer in
            return pointer.load(as: Int32.self)
        }.bigEndian
        let remaining = data.subdata(in: 4..<data.count)
        return (int32, remaining)
    }

    fileprivate static func parseRawInt64(data: Data) throws -> (Int64, Data) {
        try MsgpackElement.assertLength(data: data, length: 8)
        let int64Data = data[..<8]
        let int64 = int64Data.withUnsafeBytes { pointer in
            return pointer.load(as: Int64.self)
        }.bigEndian
        let remaining = data.subdata(in: 8..<data.count)
        return (int64, remaining)
    }
}

// Decode Msgpacktimestamp from extension type -1
extension MsgpackTimestamp: Decodable {
    public init(from decoder: any Decoder) throws {
        let extType = try decoder.getMsgpackExtType()
        guard extType == -1 else {
            throw DecodingError.typeMismatch(
                MsgpackTimestamp.self,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "The extension type is not -1 when decoding \(MsgpackTimestamp.self)"
                ))
        }
        let extData = try decoder.getMsgpackExtData()
        switch extData.count {
        case 4:
            let (uint32, _) = try MsgpackElement.parseRawUInt32(data: extData)
            self.seconds = Int64(uint32)
            self.nanoseconds = 0
        case 8:
            let (uint64, _) = try MsgpackElement.parseRawUInt64(data: extData)
            self.nanoseconds = UInt32(uint64 >> 34)
            self.seconds = Int64(uint64 & 0x0f_ffff_ffff)
        case 12:
            let (uint32, secondsData) = try MsgpackElement.parseRawUInt32(
                data: extData)
            self.nanoseconds = uint32
            let (int64, _) = try MsgpackElement.parseRawInt64(data: secondsData)
            self.seconds = int64
        default:
            throw MsgpackDecodingError.invalidTimeStamp
        }
    }
}

// MARK: Decoding error handling
enum MsgpackDecodingError: Error, CustomStringConvertible {
    // exposed error
    case decdoeWithUnexpectedMsgpackElement(UInt8)
    case decodeMapKeyNotString
    case corruptMessage
    case decodeStringError
    case decodeStringTooLarge(UInt32)
    case decodeBinaryTooLarge(UInt32)
    case decodeMapTooLarge(UInt32)
    case decodeArrayTooLarge(UInt32)
    case decodeExtensionTooLarge(UInt32)
    case invalidTimeStamp

    //  exception wrapped with context
    case decodeNumberWithInvalideRange(String)
    case decodeTypeNotMatch

    // internal error
    case decoderNotInitialized

    var description: String {
        switch self {
        case .invalidTimeStamp:
            return "The timestamp is not in correct format"
        case .decdoeWithUnexpectedMsgpackElement(let messageType):
            return "\(messageType) is not valid messagepack type"
        case .decodeMapKeyNotString:
            return "The key must be String when decoding Map in Swift"
        case .decodeStringError:
            return "The given string is not in utf-8 format"
        case .corruptMessage:
            return "The given data was not valid messagepack message"
        case .decodeStringTooLarge(let length):
            return
                "Reveived string with length \(length) which is larger than the supported max: \(Int.max)"
        case .decodeBinaryTooLarge(let length):
            return
                "Reveived binary with length \(length) which is larger than the supported max: \(Int.max)"
        case .decodeMapTooLarge(let count):
            return
                "Reveived map with \(count) keys which is larger than the supported max: \(Int.max)"
        case .decodeArrayTooLarge(let count):
            return
                "Reveived array with \(count) elements which is larger than the supported max: \(Int.max)"
        case .decodeExtensionTooLarge(let length):
            return
                "Reveived extension with length \(length) which is larger than the supported max: \(Int.max)"
        default:
            return ""
        }
    }
}
