import Foundation

// MARK: Swift Encodable implementation. Encoder, KeyedContainer, UnkeyedContainer, SingleValueContainer
class MsgpackEncoder: Encoder, MsgpackElementConvertable {
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any]
    var msgpack: MsgpackElementConvertable?

    init(
        codingPath: [any CodingKey] = [],
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) {
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func encodeMsgpackExt(extType: Int8, extData: Data) throws {
        self.msgpack = MsgpackElement.ext(extType, extData)
    }

    func container<Key>(keyedBy key: Key.Type) -> KeyedEncodingContainer<Key>
    where Key: CodingKey {
        guard let container = self.msgpack else {
            let container = MsgpackKeyedEncodingContainer<Key>(
                codingPath: codingPath, userInfo: userInfo)
            self.msgpack = container
            return KeyedEncodingContainer(container)
        }
        // Assert. Panic if the container is of diffrent type
        _ = container as! any KeyedEncodingContainerProtocol
        let newContainer = (container as! MsgpackSwitchKeyProtocol).switchKey(
            newKey: Key.self)
        self.msgpack = newContainer
        return KeyedEncodingContainer(newContainer)
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        guard let container = self.msgpack else {
            let container = MsgpackUnkeyedEncodingContainer(
                codingPath: codingPath, userInfo: userInfo)
            self.msgpack = container
            return container
        }
        // panic if the container is of diffrent type
        return container as! UnkeyedEncodingContainer

    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        guard let container = self.msgpack else {
            let container = MsgpackSingleValueEncodingContainer(
                codingPath: codingPath, userInfo: userInfo)
            self.msgpack = container
            return container
        }
        // panic if the container is of diffrent type
        return container as! SingleValueEncodingContainer
    }

    func encode<T>(_ v: T) throws -> Data where T: Encodable {
        var msgpackElement = MsgpackElement(v)
        if msgpackElement == nil {
            try v.encode(to: self)
            msgpackElement = try? convertToMsgpackElement()
        }
        guard let msgpackElement = msgpackElement else {
            throw EncodingError.invalidValue(
                type(of: v),
                .init(
                    codingPath: codingPath,
                    debugDescription:
                    "Top-level \(String(describing: T.self)) did not encode any values."
                ))
        }
        self.msgpack = msgpackElement
        return try msgpackElement.marshall()
    }

    func convertToMsgpackElement() throws -> MsgpackElement {
        guard let msgpack = msgpack else {
            throw MsgpackEncodingError.encoderNotIntilized
        }
        return try msgpack.convertToMsgpackElement()
    }
}

class MsgpackKeyedEncodingContainer<Key: CodingKey>:
    KeyedEncodingContainerProtocol, MsgpackElementConvertable,
    MsgpackSwitchKeyProtocol
{
    private var holder: [String: MsgpackElementConvertable] = [:]
    private var userInfo: [CodingUserInfoKey: Any]
    var codingPath: [any CodingKey]

    init(codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func convertToMsgpackElement() throws -> MsgpackElement {
        return .map(try holder.mapValues { v in try v.convertToMsgpackElement() })
    }

    func switchKey<NewKey: CodingKey>(newKey: NewKey.Type)
        -> MsgpackKeyedEncodingContainer<NewKey>
    {
        let container = MsgpackKeyedEncodingContainer<NewKey>(
            codingPath: codingPath, userInfo: userInfo)
        container.holder = self.holder
        return container
    }

    func encodeNil(forKey key: Key) throws {
        holder[key.stringValue] = MsgpackElement.null
    }

    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        guard let msgpackElement = MsgpackElement(value) else {
            let encoder = initEncoder(key: key)
            try value.encode(to: encoder)
            return
        }
        holder[key.stringValue] = msgpackElement
    }

    func nestedContainer<NestedKey>(
        keyedBy keyType: NestedKey.Type, forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let encoder = initEncoder(key: key)
        return encoder.container(keyedBy: keyType)
    }

    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer
    {
        let encoder = initEncoder(key: key)
        return encoder.unkeyedContainer()
    }

    func superEncoder() -> any Encoder {
        return initEncoder(key: MsgpackCodingKey(stringValue: "super"))
    }

    func superEncoder(forKey key: Key) -> any Encoder {
        return initEncoder(key: key)
    }

    private func initEncoder(key: CodingKey) -> MsgpackEncoder {
        var codingPath = self.codingPath
        codingPath.append(key)
        let encoder = MsgpackEncoder(
            codingPath: codingPath, userInfo: self.userInfo)
        holder[key.stringValue] = encoder
        return encoder
    }
}

class MsgpackUnkeyedEncodingContainer: UnkeyedEncodingContainer,
    MsgpackElementConvertable
{
    private var holder: [MsgpackElementConvertable] = []
    private var userInfo: [CodingUserInfoKey: Any]
    var codingPath: [any CodingKey]
    var count: Int { holder.count }

    init(codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func convertToMsgpackElement() throws -> MsgpackElement {
        return .array(try holder.map { e in try e.convertToMsgpackElement() })
    }

    func encodeNil() throws {
        holder.append(MsgpackElement.null)
    }

    func encode<T>(_ value: T) throws where T: Encodable {
        guard let msgpackElement = MsgpackElement(value) else {
            let encoder = initEncoder()
            try value.encode(to: encoder)
            return
        }
        self.holder.append(msgpackElement)
    }

    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type)
        -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
    {
        let encoder = initEncoder()
        return KeyedEncodingContainer(encoder.container(keyedBy: keyType))
    }

    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let encoder = initEncoder()
        return encoder.unkeyedContainer()
    }

    func superEncoder() -> any Encoder {
        return initEncoder()
    }

    private func initEncoder() -> MsgpackEncoder {
        var codingPath = self.codingPath
        codingPath.append(MsgpackCodingKey(intValue: holder.count))
        let encoder = MsgpackEncoder(
            codingPath: codingPath, userInfo: self.userInfo)
        holder.append(encoder)
        return encoder
    }
}

class MsgpackSingleValueEncodingContainer: SingleValueEncodingContainer,
    MsgpackElementConvertable
{
    private var holder: MsgpackElementConvertable?
    private var userInfo: [CodingUserInfoKey: Any]
    var codingPath: [any CodingKey]

    init(codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func encodeNil() throws {
        holder = MsgpackElement.null
    }

    func convertToMsgpackElement() throws -> MsgpackElement {
        guard let holder = holder else {
            return MsgpackElement.null
        }
        return try holder.convertToMsgpackElement()
    }

    func encode<T>(_ value: T) throws where T: Encodable {
        guard let msgpackElement = MsgpackElement(value) else {
            let encoder = MsgpackEncoder(
                codingPath: codingPath, userInfo: self.userInfo)
            try value.encode(to: encoder)
            self.holder = encoder
            return
        }
        self.holder = msgpackElement
    }
}

// MARK: internal protocols
private protocol MsgpackSwitchKeyProtocol {
    func switchKey<NewKey: CodingKey>(newKey: NewKey.Type)
        -> MsgpackKeyedEncodingContainer<NewKey>
}

protocol MsgpackElementConvertable {
    func convertToMsgpackElement() throws -> MsgpackElement
}

// MARK: (Encoding Part) Intermediate type which implements messagepack protocol. Similar to JSonObject
extension MsgpackElement: MsgpackElementConvertable {
    // MARK: Convert basic Swift type to MsgpackElement
    init?<T>(_ value: T) where T: Encodable {
        switch value {
        case let number as Int:
            self = .int(Int64(number))
        case let number as Int8:
            self = .int(Int64(number))
        case let number as Int16:
            self = .int(Int64(number))
        case let number as Int32:
            self = .int(Int64(number))
        case let number as Int64:
            self = .int(number)
        case let number as UInt8:
            self = .uint(UInt64(number))
        case let number as UInt16:
            self = .uint(UInt64(number))
        case let number as UInt32:
            self = .uint(UInt64(number))
        case let number as UInt64:
            self = .uint(number)
        case let string as String:
            self = .string(string)
        case let data as Data:
            self = .bin(data)
        case let bool as Bool:
            self = .bool(bool)
        case let float32 as Float32:
            self = .float32(float32)
        case let float64 as Float64:
            self = .float64(float64)
        default:
            // Leave other encodable types to Encodable protocol
            return nil
        }
    }

    func convertToMsgpackElement() throws -> MsgpackElement {
        return self
    }

    // MARK: Convert MsgpackElement to Data
    func marshall() throws -> Data {
        switch self {
        case .int(let number):
            return Self.encodeInt64(number)
        case .uint(let number):
            return Self.encodeUInt64(number)
        case .float32(let float32):
            return Self.encodeFloat32(float32)
        case .float64(let float64):
            return Self.encodeFloat64(float64)
        case .bool(let bool):
            return Self.encodeBool(bool)
        case .string(let s):
            return try Self.encodeString(s)
        case .null:
            return Self.encodeNil()
        case .bin(let data):
            return try Self.encodeData(data)
        case .map(let m):
            return try Self.encodeMap(m)
        case .array(let a):
            return try Self.encodeArray(a)
        case .ext(let type, let data):
            return try Self.encodeExt(type: type, data: data)
        }
    }

    private static func encodeUInt64(_ v: UInt64) -> Data {
        if v <= Int8.max {
            var uint8 = UInt8(v)
            return Data(bytes: &uint8, count: MemoryLayout<UInt8>.size)
        }
        if v <= UInt8.max {
            var uint8 = UInt8(v)
            return [0xcc] + Data(bytes: &uint8, count: MemoryLayout<UInt8>.size)
        }
        if v <= UInt16.max {
            var uint16 = UInt16(v).bigEndian
            return [0xcd]
                + Data(bytes: &uint16, count: MemoryLayout<UInt16>.size)
        }
        if v <= UInt32.max {
            var uint32 = UInt32(v).bigEndian
            return [0xce]
                + Data(bytes: &uint32, count: MemoryLayout<UInt32>.size)
        }
        var uint64 = v.bigEndian
        return [0xcf] + Data(bytes: &uint64, count: MemoryLayout<UInt64>.size)
    }

    private static func encodeInt64(_ v: Int64) -> Data {
        guard v < 0 else {
            return Self.encodeUInt64(UInt64(v))
        }
        if v >= -(1 << 5) {
            var int8 = Int8(v)
            return Data(bytes: &int8, count: MemoryLayout<Int8>.size)
        }
        if v >= Int8.min {
            var int8 = Int8(v)
            return [0xd0] + Data(bytes: &int8, count: MemoryLayout<Int8>.size)
        }
        if v >= Int16.min {
            var int16 = Int16(v).bigEndian
            return [0xd1] + Data(bytes: &int16, count: MemoryLayout<Int16>.size)
        }
        if v >= Int32.min {
            var int32 = Int32(v).bigEndian
            return [0xd2] + Data(bytes: &int32, count: MemoryLayout<Int32>.size)
        }
        var int64 = v.bigEndian
        return [0xd3] + Data(bytes: &int64, count: MemoryLayout<Int64>.size)
    }

    private static func encodeFloat32(_ v: Float32) -> Data {
        var float32BigEdianbits = v.bitPattern.bigEndian
        return [0xca]
            + Data(
                bytes: &float32BigEdianbits, count: MemoryLayout<Float32>.size)
    }

    private static func encodeFloat64(_ v: Float64) -> Data {
        var float64BigEdianbits = v.bitPattern.bigEndian
        return [0xcb]
            + Data(
                bytes: &float64BigEdianbits, count: MemoryLayout<Float64>.size)
    }

    private static func encodeString(_ v: String) throws -> Data {
        let length = v.count
        let content = v.data(using: .utf8)!
        if length < 1 << 5 {
            return [0xa0 | UInt8(length)] + content
        }
        if length <= UInt8.max {
            return [0xd9, UInt8(length)] + content
        }
        if length <= UInt16.max {
            var uint16 = UInt16(length).bigEndian
            return [0xda]
                + Data(bytes: &uint16, count: MemoryLayout<UInt16>.size)
                + content
        }
        if length <= UInt32.max {
            var uint32 = UInt32(length).bigEndian
            return [0xdb]
                + Data(bytes: &uint32, count: MemoryLayout<UInt32>.size)
                + content
        }
        throw MsgpackEncodingError.stringTooLarge
    }

    private static func encodeBool(_ v: Bool) -> Data {
        return v ? Data([0xc3]) : Data([0xc2])
    }

    private static func encodeNil() -> Data {
        return Data([0xc0])
    }

    private static func encodeData(_ v: Data) throws -> Data {
        let length = v.count
        var lengthPrefix: Data
        if length <= UInt8.max {
            var uint8 = UInt8(length)
            lengthPrefix =
                [0xc4] + Data(bytes: &uint8, count: MemoryLayout<UInt8>.size)
        } else if length <= UInt16.max {
            var uint16 = UInt16(length).bigEndian
            lengthPrefix =
                [0xc5] + Data(bytes: &uint16, count: MemoryLayout<UInt16>.size)
        } else if length <= UInt32.max {
            var uint32 = UInt32(length).bigEndian
            lengthPrefix =
                [0xc6] + Data(bytes: &uint32, count: MemoryLayout<UInt32>.size)
        } else {
            throw MsgpackEncodingError.dataTooLarge
        }
        return lengthPrefix + v
    }

    private static func encodeMap(_ v: [String: MsgpackElement]) throws -> Data {
        let length = v.count
        var mapPrefix: Data
        if length < 1 << 4 {
            mapPrefix = Data([0x80 | UInt8(length)])
        } else if length <= UInt16.max {
            var uint16 = UInt16(length).bigEndian
            mapPrefix =
                [0xde] + Data(bytes: &uint16, count: MemoryLayout<UInt16>.size)
        } else if length <= UInt32.max {
            var uint32 = UInt32(length).bigEndian
            mapPrefix =
                [0xdf] + Data(bytes: &uint32, count: MemoryLayout<UInt32>.size)
        } else {
            throw MsgpackEncodingError.mapTooManyElements
        }
        var list: [Data] = []
        var totalLength = mapPrefix.count
        for (k, v) in v {
            let kData = try Self.encodeString(k)
            totalLength += kData.count
            list.append(kData)
            let vData = try v.marshall()
            totalLength += vData.count
            list.append(vData)
        }
        var result = Data(capacity: totalLength)
        result.append(mapPrefix)
        for v in list {
            result.append(v)
        }
        return result
    }

    private static func encodeArray(_ v: [MsgpackElement]) throws -> Data {
        let length = v.count
        var arrayPrefix: Data
        if length < 1 << 4 {
            arrayPrefix = Data([0x90 | UInt8(length)])
        } else if length <= UInt16.max {
            var uint16 = UInt16(length).bigEndian
            arrayPrefix =
                [0xdc] + Data(bytes: &uint16, count: MemoryLayout<UInt16>.size)
        } else if length <= UInt32.max {
            var uint32 = UInt32(length).bigEndian
            arrayPrefix =
                [0xdd] + Data(bytes: &uint32, count: MemoryLayout<UInt32>.size)
        } else {
            throw MsgpackEncodingError.arrayTooManyElements
        }
        var list: [Data] = []
        var totalLength = arrayPrefix.count
        for v in v {
            let vData = try v.marshall()
            totalLength += vData.count
            list.append(vData)
        }
        var result = Data(capacity: totalLength)
        result.append(arrayPrefix)
        for v in list {
            result.append(v)
        }
        return result
    }

    private static func encodeExt(type: Int8, data: Data) throws -> Data {
        let length = data.count
        var int8 = Int8(type)
        let typeData = Data(bytes: &int8, count: MemoryLayout<Int8>.size)
        if length == 1 {
            return [0xd4] + typeData + data
        }
        if length == 2 {
            return [0xd5] + typeData + data
        }
        if length == 4 {
            return [0xd6] + typeData + data
        }
        if length == 8 {
            return [0xd7] + typeData + data
        }
        if length == 16 {
            return [0xd8] + typeData + data
        }
        if length <= UInt8.max {
            return [0xc7, UInt8(length)] + typeData + data
        }
        if length <= UInt16.max {
            var uint16 = UInt16(length).bigEndian
            let uint16Data = Data(
                bytes: &uint16, count: MemoryLayout<UInt16>.size)
            return [0xc8] + uint16Data + typeData + data
        }
        if length <= UInt32.max {
            var uint32 = UInt32(length).bigEndian
            let uint32Data = Data(
                bytes: &uint32, count: MemoryLayout<UInt32>.size)
            return [0xc9] + uint32Data + typeData + data
        }
        throw MsgpackEncodingError.extensionTooLarge
    }
}

// Encode Msgpacktimestamp to extension type -1
extension MsgpackTimestamp: Encodable {
    public func encode(to encoder: any Encoder) throws {
        let nanoseconds = self.nanoseconds
        let seconds = self.seconds
        var data: Data
        if nanoseconds == 0 && seconds >= 0 && seconds <= UInt32.max {
            var secondsUInt32 = UInt32(seconds).bigEndian
            data = Data(bytes: &secondsUInt32, count: MemoryLayout<UInt32>.size)
        } else if seconds >= 0 && seconds < (UInt64(1)) << 34 {
            let secondsUInt64 = UInt64(seconds).bigEndian
            let nanoSecondsUInt64 = (UInt64(nanoseconds) << 34).bigEndian
            var time = nanoSecondsUInt64 | secondsUInt64
            data = Data(bytes: &time, count: MemoryLayout<UInt64>.size)
        } else {
            var secondsInt64 = seconds.bigEndian
            var nanoSecondsUInt32 = UInt32(nanoseconds).bigEndian
            data =
                Data(
                    bytes: &nanoSecondsUInt32, count: MemoryLayout<UInt32>.size)
                + Data(bytes: &secondsInt64, count: MemoryLayout<Int64>.size)
        }
        return try encoder.encodeMsgpackExt(extType: -1, extData: data)
    }
}

// MARK: Encoding error handling
enum MsgpackEncodingError: Error, CustomStringConvertible {
    // exposed exception
    case dataTooLarge
    case mapTooManyElements
    case arrayTooManyElements
    case stringTooLarge
    case extensionTooLarge

    // internal exception
    case encoderNotIntilized

    var description: String {
        switch self {
        case .dataTooLarge:
            return "Messagpack can't encode binary larger than 4GB"
        case .mapTooManyElements:
            return "Messagpack can't encode map with more than 4G keys"
        case .arrayTooManyElements:
            return "Messagpack can't encode array with more than 4G elements"
        case .stringTooLarge:
            return "Messagpack can't encode string larger than 4GB"
        case .extensionTooLarge:
            return "Messagpack can't encode extension larger than 4GB"
        default:
            return ""
        }
    }
}
