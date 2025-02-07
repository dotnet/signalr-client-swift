import Foundation
import XCTest

@testable import SignalRClient

class MsgpackEncoderTests: XCTestCase {
    // MARK: Convert MsgpackElement to Data
    func testEncodeUInt() throws {
        var data: [UInt64: Data] = [:]
        data[0x00] = Data([0x00])
        data[0x7f] = Data([0x7f])
        data[0x80] = Data([0xcc, 0x80])
        data[0xff] = Data([0xcc, 0xff])
        data[0x100] = Data([0xcd, 0x01, 0x00])
        data[0xffff] = Data([0xcd, 0xff, 0xff])
        data[0x10000] = Data([0xce, 0x00, 0x01, 0x00, 0x00])
        data[0xffff_ffff] = Data([0xce, 0xff, 0xff, 0xff, 0xff])
        data[0x1_0000_0000] = Data([
            0xcf, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        ])
        for (uint64, expected) in data {
            let result = try MsgpackElement.uint(uint64).marshall()
            XCTAssertEqual(result, expected)
        }
    }

    func testEncodeInt() throws {
        var data: [Int64: Data] = [:]
        data[-0x20] = Data([0xe0])
        data[-0x21] = Data([0xd0, 0xdf])
        data[-0x80] = Data([0xd0, 0x80])
        data[-0x81] = Data([0xd1, 0xff, 0x7f])
        data[-0x8000] = Data([0xd1, 0x80, 0x00])
        data[-0x8001] = Data([0xd2, 0xff, 0xff, 0x7f, 0xff])
        data[-0x8000_0000] = Data([0xd2, 0x80, 0x00, 0x00, 0x00])
        data[-0x8000_0001] = Data([
            0xd3, 0xff, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff,
        ])
        data[0x00] = Data([0x00])
        data[0x7f] = Data([0x7f])
        for (int64, expected) in data {
            let result = try MsgpackElement.int(int64).marshall()
            XCTAssertEqual(result, expected)
        }
    }

    func testEncodeFloat32() throws {
        var data: [Float32: Data] = [:]
        data[0.0] = Data([0xca, 0x00, 0x00, 0x00, 0x00])
        data[1.1] = Data([0xca, 0x3f, 0x8c, 0xcc, 0xcd])
        data[-0.9] = Data([0xca, 0xbf, 0x66, 0x66, 0x66])
        for (float32, expected) in data {
            let result = try MsgpackElement.float32(float32).marshall()
            XCTAssertEqual(result, expected)
        }
    }

    func testEncodeFloat64() throws {
        var data: [Float64: Data] = [:]
        data[0.0] = Data([0xcb, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        data[1.1] = Data([0xcb, 0x3f, 0xf1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9a])
        data[-0.9] = Data([
            0xcb, 0xbf, 0xec, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcd,
        ])
        for (float64, expected) in data {
            let result = try MsgpackElement.float64(float64).marshall()
            XCTAssertEqual(result, expected)
        }
    }

    func testEncodeString() throws {
        var data: [Int: Data] = [:]
        data[0] = Data([0xa0])
        data[1 << 5 - 1] = [0xbf] + Data(repeating: 0x61, count: 1 << 5 - 1)
        data[1 << 5] = [0xd9, 0x20] + Data(repeating: 0x61, count: 1 << 5)
        data[1 << 8 - 1] =
            [0xd9, 0xff] + Data(repeating: 0x61, count: 1 << 8 - 1)
        data[1 << 8] =
            [0xda, 0x01, 0x00] + Data(repeating: 0x61, count: 1 << 8)
        data[1 << 16 - 1] =
            [0xda, 0xff, 0xff] + Data(repeating: 0x61, count: 1 << 16 - 1)
        data[1 << 16] =
            [0xdb, 0x00, 0x01, 0x00, 0x00]
            + Data(repeating: 0x61, count: 1 << 16)
        for (length, expected) in data {
            let string = String(repeating: Character("a"), count: length)
            let result = try MsgpackElement.string(string).marshall()
            XCTAssertEqual(result, expected)
        }
    }

    func testEncodeBool() throws {
        var data: [Bool: Data] = [:]
        data[true] = Data([0xc3])
        data[false] = Data([0xc2])
        for (bool, expected) in data {
            let result = try MsgpackElement.bool(bool).marshall()
            XCTAssertEqual(result, expected)
        }
    }

    func testEncodeNil() throws {
        let expected = Data([0xc0])
        let result = try MsgpackElement.null.marshall()
        XCTAssertEqual(result, expected)
    }

    func testEncodeData() throws {
        var data: [Int: Data] = [:]
        data[0] = Data([0xc4, 0x00])
        data[1 << 8 - 1] =
            [0xc4, 0xff] + Data(repeating: UInt8(1), count: 1 << 8 - 1)
        data[1 << 8] =
            [0xc5, 0x01, 0x00] + Data(repeating: UInt8(1), count: 1 << 8)
        data[1 << 16 - 1] =
            [0xc5, 0xff, 0xff] + Data(repeating: UInt8(1), count: 1 << 16 - 1)
        data[1 << 16] =
            [0xc6, 0x00, 0x01, 0x00, 0x00]
            + Data(repeating: UInt8(1), count: 1 << 16)
        for (length, expected) in data {
            let data = Data(repeating: UInt8(1), count: length)
            let result = try MsgpackElement.bin(data).marshall()
            XCTAssertEqual(result, expected)
        }
    }

    func testEncodeMap() throws {
        var map: [String: MsgpackElement] = [:]
        var result = try MsgpackElement.map(map).marshall()
        XCTAssertEqual(result, Data([0x80]))
        for i in 0..<1 << 4 - 1 {
            map[String(i)] = MsgpackElement.bool(true)
        }
        result = try MsgpackElement.map(map).marshall()
        XCTAssertEqual(result.count, 51)
        XCTAssertEqual(result[0], 0x8f)

        map.removeAll()
        for i in 0..<1 << 4 {
            map[String(i)] = MsgpackElement.bool(true)
        }
        result = try MsgpackElement.map(map).marshall()
        XCTAssertEqual(result.count, 57)
        XCTAssertEqual(result[0...2], Data([0xde, 0x00, 0x10]))

        map.removeAll()
        for i in 0..<1 << 16 - 1 {
            map[String(i)] = MsgpackElement.bool(true)
        }
        result = try MsgpackElement.map(map).marshall()
        XCTAssertEqual(result.count, 447638)
        XCTAssertEqual(result[0...2], Data([0xde, 0xff, 0xff]))

        map.removeAll()
        for i in 0..<1 << 16 {
            map[String(i)] = MsgpackElement.bool(true)
        }
        result = try MsgpackElement.map(map).marshall()
        XCTAssertEqual(result.count, 447647)
        XCTAssertEqual(result[0...4], Data([0xdf, 0x00, 0x01, 0x00, 0x00]))
    }

    func testEncodeArray() throws {
        var data: [MsgpackElement] = []
        var result = try MsgpackElement.array(data).marshall()
        XCTAssertEqual(result, Data([0x90]))

        data = [MsgpackElement](repeating: .bool(true), count: 1 << 4 - 1)
        result = try MsgpackElement.array(data).marshall()
        XCTAssertEqual(
            result, [0x9f] + Data(repeating: 0xc3, count: 1 << 4 - 1))

        data = [MsgpackElement](repeating: .bool(true), count: 1 << 4)
        result = try MsgpackElement.array(data).marshall()
        XCTAssertEqual(
            result, [0xdc, 0x00, 0x10] + Data(repeating: 0xc3, count: 1 << 4))

        data = [MsgpackElement](repeating: .bool(true), count: 1 << 16 - 1)
        result = try MsgpackElement.array(data).marshall()
        XCTAssertEqual(
            result,
            [0xdc, 0xff, 0xff] + Data(repeating: 0xc3, count: 1 << 16 - 1))

        data = [MsgpackElement](repeating: .bool(true), count: 1 << 16)
        result = try MsgpackElement.array(data).marshall()
        XCTAssertEqual(
            result,
            [0xdd, 0x00, 0x01, 0x00, 0x00]
                + Data(repeating: 0xc3, count: 1 << 16))
    }

    func testEncodeExtension() throws {
        var data: [Int: Data] = [:]
        data[1] = Data([0xd4, 0xff])
        data[2] = Data([0xd5, 0xff])
        data[4] = Data([0xd6, 0xff])
        data[8] = Data([0xd7, 0xff])
        data[16] = Data([0xd8, 0xff])
        data[0] = Data([0xc7, 0x00, 0xff])
        data[1 << 8 - 1] = Data([0xc7, 0xff, 0xff])
        data[1 << 8] = Data([0xc8, 0x01, 0x00, 0xff])
        data[1 << 16 - 1] = Data([0xc8, 0xff, 0xff, 0xff])
        data[1 << 16] = Data([0xc9, 0x00, 0x01, 0x00, 0x00, 0xff])
        data[Int(UInt32.max)] = Data([0xc9, 0xff, 0xff, 0xff, 0xff, 0xff])
        for (len, extPrefix) in data {
            let extData = Data(repeating: 1, count: len)
            let msgpackElement = MsgpackElement.ext(-1, extData)
            let result = try msgpackElement.marshall()
            let expected = extPrefix + extData
            XCTAssertEqual(result, expected)
        }
    }

    // Used for debugging
    func testAgainstExpected(v: Encodable, expected: Data, result: Data) throws
    {
        if expected != result {
            print(expected.hexEncodedString())
            print(result.hexEncodedString())
            XCTFail("encoded result for \(v) not equal to expected")
        }
    }

    // MARK: Convert from basic Swift type to MsgpackElement
    func testInitInt() throws {
        XCTAssertEqual(MsgpackElement(Int8(-1)), MsgpackElement.int(Int64(-1)))
        XCTAssertEqual(MsgpackElement(Int16(-1)), MsgpackElement.int(Int64(-1)))
        XCTAssertEqual(MsgpackElement(Int32(-1)), MsgpackElement.int(Int64(-1)))
        XCTAssertEqual(MsgpackElement(Int64(-1)), MsgpackElement.int(Int64(-1)))
    }

    func testInitUInt() throws {
        XCTAssertEqual(MsgpackElement(UInt8(1)), MsgpackElement.uint(UInt64(1)))
        XCTAssertEqual(MsgpackElement(UInt16(1)), MsgpackElement.uint(UInt64(1)))
        XCTAssertEqual(MsgpackElement(UInt32(1)), MsgpackElement.uint(UInt64(1)))
        XCTAssertEqual(MsgpackElement(UInt64(1)), MsgpackElement.uint(UInt64(1)))
    }

    // The compiler implement its encodable as Float32
    func testFloat16() throws {
        let encoder = MsgpackEncoder()
        _ = try encoder.encode(Float16(1))
        let msgpackElement = try encoder.msgpack?.convertToMsgpackElement()
        XCTAssertEqual(msgpackElement, MsgpackElement.float32(Float32(1)))
    }

    func testInitFloat32() throws {
        XCTAssertEqual(MsgpackElement(Float32(1)), MsgpackElement.float32(Float32(1)))
    }

    func testInitFloat64() throws {
        XCTAssertEqual(MsgpackElement(Float64(1)), MsgpackElement.float64(Float64(1)))
    }

    func testInitBool() throws {
        XCTAssertEqual(MsgpackElement(true), MsgpackElement.bool(true))
        XCTAssertEqual(MsgpackElement(false), MsgpackElement.bool(false))
    }

    func testInitString() throws {
        XCTAssertEqual(MsgpackElement("abc"), MsgpackElement.string("abc"))
    }

    func testInitData() throws {
        XCTAssertEqual(MsgpackElement(Data([123])), MsgpackElement.bin(Data([123])))
    }

    func testMapArrayNotInited() throws {
        XCTAssertEqual(MsgpackElement([String: String]()), nil)
        XCTAssertEqual(MsgpackElement([String]()), nil)
    }

    // MARK: MsgpackEncoder encode
    private class DefaultEncodeExample: Encodable {
        var int: Int
        var intNil: Int?
        var bool: Bool
        var boolNil: Bool?
        var string: String
        var data: Data
        var float32: Float32
        var float64: Float64
        var map1: [String: String]
        var map2: [String: Bool]
        var map3: [String: [String: Bool]]
        var array1: [Int?]
        var array2: [[Int?]]
        var date: Date

        init() {
            self.int = 2
            self.boolNil = true
            self.bool = true
            self.string = "123"
            self.data = Data([0x90])
            self.float32 = 1.1
            self.float64 = 1.1
            self.map1 = [:]
            self.map2 = ["a": true]
            self.map3 = ["b": map2]
            self.array1 = [1, 2, nil, 4]
            self.array2 = [self.array1]
            self.date = Date(timeIntervalSince1970: 100.1)
        }
    }

    func testDefaultEncode() throws {
        let encoder = MsgpackEncoder()
        let example = DefaultEncodeExample()
        _ = try encoder.encode(example)
        let msgpackElement = try encoder.convertToMsgpackElement()
        guard case let MsgpackElement.map(m) = msgpackElement else {
            XCTFail("Decoded to unexpected msgpack type:\(msgpackElement)")
            return
        }
        XCTAssertEqual(m.count, 13)
        XCTAssertEqual(m["int"], MsgpackElement.int(Int64(2)))
        XCTAssertEqual(m["intNil"], nil)
        XCTAssertEqual(m["bool"], MsgpackElement.bool(true))
        XCTAssertEqual(m["boolNil"], MsgpackElement.bool(true))
        XCTAssertEqual(m["string"], MsgpackElement.string("123"))
        XCTAssertEqual(m["data"], MsgpackElement.bin(Data([0x90])))
        XCTAssertEqual(m["float32"], MsgpackElement.float32(Float32(1.1)))
        XCTAssertEqual(m["float64"], MsgpackElement.float64(Float64(1.1)))
        XCTAssertEqual(m["map1"], MsgpackElement.map([String: MsgpackElement]()))
        var map2: [String: MsgpackElement] = [:]
        map2["a"] = MsgpackElement.bool(true)
        XCTAssertEqual(m["map2"], MsgpackElement.map(map2))
        var map3: [String: MsgpackElement] = [:]
        map3["b"] = MsgpackElement.map(map2)
        XCTAssertEqual(m["map3"], MsgpackElement.map(map3))
        let array1 = [
            MsgpackElement.int(1), MsgpackElement.int(2), MsgpackElement.null,
            MsgpackElement.int(4),
        ]
        XCTAssertEqual(m["array1"], MsgpackElement.array(array1))
        var array2: [MsgpackElement] = []
        array2.append(MsgpackElement.array(array1))
        XCTAssertEqual(m["array2"], MsgpackElement.array(array2))
    }

    private class ManualEncodeExample: Encodable {
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(123, forKey: .Key1)
            var nestedKeyedContainer1 = container.nestedContainer(
                keyedBy: Keys.self, forKey: Keys.Key2)
            try nestedKeyedContainer1.encode("123", forKey: Keys.nestedKey1)
            var nestedUnkeyedContainer = container.nestedUnkeyedContainer(
                forKey: Keys.Key3)
            try nestedUnkeyedContainer.encode(Data([0x12]))
        }

        enum Keys: CodingKey {
            case Key1
            case Key2
            case Key3

            case nestedKey1
        }
    }

    func testManualEncode() throws {
        let example2 = ManualEncodeExample()
        let encoder = MsgpackEncoder()
        _ = try encoder.encode(example2)
        let msgpackElement = try encoder.convertToMsgpackElement()

        var map: [String: MsgpackElement] = [:]
        map["Key1"] = MsgpackElement.int(123)
        var nestedMap: [String: MsgpackElement] = [:]
        nestedMap["nestedKey1"] = MsgpackElement.string("123")
        map["Key2"] = MsgpackElement.map(nestedMap)
        var nestedArray: [MsgpackElement] = []
        nestedArray.append(MsgpackElement.bin(Data([0x12])))
        map["Key3"] = MsgpackElement.array(nestedArray)
        let expected = MsgpackElement.map(map)
        XCTAssertEqual(msgpackElement, expected)
    }

    private class BaseClassExample: Encodable {
        var parent: Bool = true
    }

    private class InherienceWithSameContainerExample: BaseClassExample {
        var child: Bool = true

        override func encode(to encoder: any Encoder) throws {
            try super.encode(to: encoder)
            // Switching to a KeyedContainer with different key type
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(child, forKey: .child)
        }

        enum Keys: CodingKey {
            case child
        }
    }

    func testInherienceUsingSameTopContainer() throws {  // Undocumented behavior. Keep aligh with the jsonEncoder
        let encoder = MsgpackEncoder()
        let example = InherienceWithSameContainerExample()
        _ = try encoder.encode(example)
        let msgpackElement = try encoder.convertToMsgpackElement()
        guard case let MsgpackElement.map(m) = msgpackElement else {
            XCTFail("The msgpackElement should be map")
            return
        }
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m["parent"], MsgpackElement.bool(true))
        XCTAssertEqual(m["child"], MsgpackElement.bool(true))
        print(msgpackElement)
    }

    private class KeyedSuperExample: BaseClassExample {
        var child: Bool = true
        override func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(child, forKey: .child)
            let superencoder = container.superEncoder()
            try super.encode(to: superencoder)
            let superencoder2 = container.superEncoder(forKey: Keys.super2)
            try super.encode(to: superencoder2)
        }
        enum Keys: CodingKey {
            case child
            case super2
        }
    }

    func testKeyedInherience() throws {
        let encoder = MsgpackEncoder()
        let example = KeyedSuperExample()
        _ = try encoder.encode(example)
        let msgpackElement = try encoder.convertToMsgpackElement()
        guard case let MsgpackElement.map(m) = msgpackElement else {
            XCTFail("The msgpackElement should be map")
            return
        }

        XCTAssertEqual(m.count, 3)
        var parent: [String: MsgpackElement] = [:]
        parent["parent"] = MsgpackElement.bool(true)
        let parentMsgpackElement = MsgpackElement.map(parent)
        XCTAssertEqual(m["super"], parentMsgpackElement)
        XCTAssertEqual(m["super2"], parentMsgpackElement)
        XCTAssertEqual(m["child"], MsgpackElement.bool(true))
    }

    private class UnkeyedSuperExample: BaseClassExample {
        override func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(true)
            let encoder = container.superEncoder()
            try super.encode(to: encoder)
        }
    }

    func testUnkeyedInherience() throws {
        let encoder = MsgpackEncoder()
        let example = UnkeyedSuperExample()
        _ = try encoder.encode(example)
        let msgpackElement = try encoder.convertToMsgpackElement()
        guard case let MsgpackElement.array(array) = msgpackElement else {
            XCTFail("The msgpackElement should be array")
            return
        }

        _ = try JSONEncoder().encode(example)
        XCTAssertEqual(array.count, 2)
        var parent: [String: MsgpackElement] = [:]
        parent["parent"] = MsgpackElement.bool(true)
        let parentMsgpackElement = MsgpackElement.map(parent)
        XCTAssertEqual(array[0], MsgpackElement.bool(true))
        XCTAssertEqual(array[1], parentMsgpackElement)
    }

    // MARK: Extension
    func testEncodeTimestamp() throws {
        var data: [Double: Data] = [:]
        data[0] = Data([0x0, 0x0, 0x0, 0x0])
        data[-0.5] = Data([
            0x1d, 0xcd, 0x65, 0x0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
            0xff,
        ])
        data[-1.5] = Data([
            0x1d, 0xcd, 0x65, 0x0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
            0xfe,
        ])
        data[1.5] = Data([0x77, 0x35, 0x94, 0x0, 0x0, 0x0, 0x0, 0x1])
        data[Double(UInt32.max)] = Data([0xff, 0xff, 0xff, 0xff])
        data[Double(UInt32.max) + 1] = Data([
            0x0, 0x0, 0x0, 0x1, 0x0, 0x0, 0x0, 0x0,
        ])
        data[Double(UInt64(1) << 34 - 1)] = Data([
            0x0, 0x0, 0x0, 0x3, 0xff, 0xff, 0xff, 0xff,
        ])
        data[Double(UInt64(1) << 34)] = Data([
            0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x4, 0x0, 0x0, 0x0, 0x0,
        ])

        for (time, expected) in data {
            let seconds = Int64(time.rounded(FloatingPointRoundingRule.down))
            let nanoseconds = UInt32(
                ((time - Double(seconds)) * 1_000_000_000).rounded(
                    FloatingPointRoundingRule.down))
            let timestamp = MsgpackTimestamp(
                seconds: seconds, nanoseconds: nanoseconds)
            let encoder = MsgpackEncoder()
            _ = try encoder.encode(timestamp)
            let msgpackElement = try encoder.convertToMsgpackElement()
            guard case let MsgpackElement.ext(extType, extData) = msgpackElement
            else {
                XCTFail("Encoder should produce extension type")
                return
            }
            XCTAssertEqual(extType, -1)
            XCTAssertEqual(extData, expected)
        }
    }

    // MARK: User Info
    struct UserInfoExample: Encodable {
        func encode(to encoder: any Encoder) throws {
            let userInfo = encoder.userInfo
            AsserUserInfo(userInfo)
            var container1 = encoder.container(keyedBy: Keys.self)
            let superEncoder = container1.superEncoder()
            AsserUserInfo(superEncoder.userInfo)
            _ = superEncoder.singleValueContainer()
            let superEncoder2 = container1.superEncoder(forKey: .Key1)
            AsserUserInfo(superEncoder2.userInfo)
            var container3 = superEncoder2.unkeyedContainer()
            let superEncoder3 = container3.superEncoder()
            _ = superEncoder3.singleValueContainer()
            AsserUserInfo(superEncoder3.userInfo)
        }

        enum Keys: CodingKey {
            case Key1
        }

        func AsserUserInfo(_ userInfo: [CodingUserInfoKey: Any]) {
            XCTAssertEqual(userInfo.count, 1)
            let key = CodingUserInfoKey(rawValue: "key")!
            XCTAssertEqual(userInfo[key] as! String, "value")
        }
    }

    func testUserInfo() throws {
        var userInfo: [CodingUserInfoKey: Any] = [:]
        let key = CodingUserInfoKey(rawValue: "key")!
        userInfo[key] = "value"
        let encoder = JSONEncoder()
        encoder.userInfo[key] = "value"
        let example = UserInfoExample()
        _ = try encoder.encode(example)
    }

    // MARK: CodingKey
    struct CodingKeyExample: Encodable {
        func encode(to encoder: any Encoder) throws {
            XCTAssertEqual(encoder.codingPath.count, 0)
            var container1 = encoder.container(keyedBy: Keys.self)
            XCTAssertEqual(container1.codingPath.count, 0)

            let superEncoder = container1.superEncoder()
            XCTAssertEqual(superEncoder.codingPath.count, 1)
            XCTAssertEqual(
                superEncoder.codingPath[0] as! MsgpackCodingKey,
                MsgpackCodingKey(stringValue: "super"))
            let superSingleValueContainer = superEncoder.singleValueContainer()
            XCTAssertEqual(superSingleValueContainer.codingPath.count, 1)
            XCTAssertEqual(
                superSingleValueContainer.codingPath[0] as! MsgpackCodingKey,
                MsgpackCodingKey(stringValue: "super"))

            let superEncoder2 = container1.superEncoder(forKey: .superKey)
            XCTAssertEqual(superEncoder2.codingPath.count, 1)
            XCTAssertEqual(superEncoder2.codingPath[0] as! Keys, Keys.superKey)
            let superSingleValueContainer2 =
                superEncoder2.singleValueContainer()
            XCTAssertEqual(superSingleValueContainer2.codingPath.count, 1)
            XCTAssertEqual(
                superSingleValueContainer2.codingPath[0] as! Keys, Keys.superKey
            )

            XCTAssertEqual(container1.codingPath.count, 0)
            var container2 = container1.nestedContainer(
                keyedBy: Keys.self, forKey: .Key1)
            XCTAssertEqual(container2.codingPath.count, 1)
            XCTAssertEqual(container2.codingPath[0] as! Keys, Keys.Key1)

            var container3 = container2.nestedUnkeyedContainer(forKey: .Key2)
            XCTAssertEqual(container3.codingPath.count, 2)
            XCTAssertEqual(container3.codingPath[0] as! Keys, Keys.Key1)
            XCTAssertEqual(container3.codingPath[1] as! Keys, Keys.Key2)

            let container4 = container3.nestedUnkeyedContainer()
            XCTAssertEqual(container4.codingPath.count, 3)
            XCTAssertEqual(container4.codingPath[0] as! Keys, Keys.Key1)
            XCTAssertEqual(container4.codingPath[1] as! Keys, Keys.Key2)
            XCTAssertEqual(
                container4.codingPath[2] as! MsgpackCodingKey,
                MsgpackCodingKey(intValue: 0))
        }

        enum Keys: CodingKey {
            case Key1, Key2, superKey
        }
    }

    func testCodingKey() throws {
        let example = CodingKeyExample()
        let encoder = MsgpackEncoder()
        _ = try encoder.encode(example)
    }

    // MARK: Container properties
    struct UnkeyedContainerCountExample: Encodable {
        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            XCTAssertEqual(container.count, 0)
            try container.encode(true)
            XCTAssertEqual(container.count, 1)
            _ = container.superEncoder().singleValueContainer()
            XCTAssertEqual(container.count, 2)
        }
    }

    func testUnkeyedContainerCount() throws {
        let example = UnkeyedContainerCountExample()
        let encoder = MsgpackEncoder()
        _ = try encoder.encode(example)
    }
}

// Used for debugging
extension Data {
    fileprivate func hexEncodedString() -> String {
        return self.map { v in String(format: "%02hhx", v) }.joined()
    }
    fileprivate func hexEncodedArray() -> String {
        return self.map { v in String(format: "0x%02hhx", v) }.joined(
            separator: ",")
    }
}
