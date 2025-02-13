// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import XCTest

@testable import SignalRClient

class MsgpackDecoderTests: XCTestCase {
    // MARK: Convert Data to MsgpackElement
    func testParseUInt() throws {
        let data: [UInt64] = [
            0, 0x7f, 0x80, 0xff, 0x100, 0xffff, 0x10000, 0xffff_ffff,
            0x1_0000_0000,
        ]
        for i in data {
            let msgpackElement = MsgpackElement.uint(i)
            let binary = try msgpackElement.marshall()
            let (decodeddType, remaining) = try MsgpackElement.parse(data: binary)
            XCTAssertEqual(remaining.count, 0)
            XCTAssertEqual(decodeddType, msgpackElement)
        }
    }

    func testParseNegativeInt() throws {
        let data: [Int64] = [
            -0x20, -0x21, -0x80, -0x81, -0x8000, -0x8000, -0x10000, -0x8000,
        ]
        for i in data {
            let msgpackElement = MsgpackElement.int(i)
            let binary = try msgpackElement.marshall()
            let (decodeddType, remaining) = try MsgpackElement.parse(data: binary)
            XCTAssertEqual(remaining.count, 0)
            XCTAssertEqual(decodeddType, msgpackElement)
        }
    }

    func testParseIntNotNegative() throws {
        var data: [Int64: Data] = [:]
        data[0] = Data([0xd0, 0x00])
        data[1 << 7 - 1] = Data([0xd0, 0x7f])
        data[1 << 7] = Data([0xd1, 0x00, 0x80])
        data[1 << 15 - 1] = Data([0xd1, 0x7f, 0xff])
        data[1 << 15] = Data([0xd2, 0x00, 0x00, 0x80, 0x00])
        data[1 << 31 - 1] = Data([0xd2, 0x7f, 0xff, 0xff, 0xff])
        data[1 << 31] = Data([
            0xd3, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00,
        ])
        for (k, v) in data {
            let (decodeddType, remaining) = try MsgpackElement.parse(data: v)
            XCTAssertEqual(remaining.count, 0)
            let msgpackElement = MsgpackElement.int(k)
            XCTAssertEqual(decodeddType, msgpackElement)
        }
    }

    func testParseFloat32() throws {
        let data: [Float32] = [0.0, 1.1 - 0.9]
        for i in data {
            let msgpackElement = MsgpackElement.float32(i)
            let binary = try msgpackElement.marshall()
            let (decodeddType, remaining) = try MsgpackElement.parse(data: binary)
            XCTAssertEqual(remaining.count, 0)
            XCTAssertEqual(decodeddType, msgpackElement)
        }
    }

    func testParseFloat64() throws {
        let data: [Float64] = [0.0, 1.1 - 0.9]
        for i in data {
            let msgpackElement = MsgpackElement.float64(i)
            let binary = try msgpackElement.marshall()
            let (decodeddType, remaining) = try MsgpackElement.parse(data: binary)
            XCTAssertEqual(remaining.count, 0)
            XCTAssertEqual(decodeddType, msgpackElement)
        }
    }

    func testParseString() throws {
        let data: [Int] = [
            0, 1 << 5 - 1, 1 << 5, 1 << 8 - 1, 1 << 8, 1 << 16 - 1, 1 << 16,
        ]
        for length in data {
            let msgpackElement = MsgpackElement.string(
                String(repeating: Character("a"), count: length))
            let binary = try msgpackElement.marshall()
            let (decodedType, remaining) = try MsgpackElement.parse(data: binary)
            XCTAssertEqual(remaining.count, 0)
            XCTAssertEqual(decodedType, msgpackElement)
        }
    }

    func testParseNil() throws {
        let msgpackElement = MsgpackElement.null
        let binary = try msgpackElement.marshall()
        let (decodedType, remaining) = try MsgpackElement.parse(data: binary)
        XCTAssertEqual(remaining.count, 0)
        XCTAssertEqual(decodedType, msgpackElement)
    }

    func testParseBool() throws {
        let data: [Bool] = [true, false]
        for b in data {
            let msgpackElement = MsgpackElement.bool(b)
            let binary = try msgpackElement.marshall()
            let (decodedType, remaining) = try MsgpackElement.parse(data: binary)
            XCTAssertEqual(remaining.count, 0)
            XCTAssertEqual(decodedType, msgpackElement)
        }
    }

    func testParseData() throws {
        let data = [0, 1 << 8 - 1, 1 << 8, 1 << 16 - 1, 1 << 16]
        for length in data {
            let msgpackElement = MsgpackElement.bin(
                Data(repeating: UInt8(2), count: length))
            let binary = try msgpackElement.marshall()
            let (decodedType, remaining) = try MsgpackElement.parse(data: binary)
            XCTAssertEqual(remaining.count, 0)
            XCTAssertEqual(decodedType, msgpackElement)
        }
    }

    func testParseMap() throws {
        let data = [0, 1 << 4 - 1, 1 << 4, 1 << 16 - 1, 1 << 16]
        for i in data {
            var map: [String: MsgpackElement] = [:]
            for i in 0..<i {
                map[String(i)] = MsgpackElement.bool(true)
            }
            let msgpackElement = MsgpackElement.map(map)
            let content = try msgpackElement.marshall()
            let (decoded, remaining) = try MsgpackElement.parse(data: content)
            XCTAssertEqual(remaining.count, 0)
            XCTAssertEqual(decoded, msgpackElement)
        }
    }

    func testParseArray() throws {
        let data = [0, 1 << 4 - 1, 1 << 4, 1 << 16 - 1, 1 << 16]
        for i in data {
            var array: [MsgpackElement] = []
            array.reserveCapacity(i)
            for _ in 0..<i {
                array.append(MsgpackElement.bool(true))
            }
            let msgpackElement = MsgpackElement.array(array)
            let content = try msgpackElement.marshall()
            let (decoded, remaining) = try MsgpackElement.parse(data: content)
            XCTAssertEqual(remaining.count, 0)
            XCTAssertEqual(decoded, msgpackElement)
        }
    }

    func testDecodeExt() throws {
        let data: [Int] = [
            1, 2, 4, 8, 16, 0, 1 << 8 - 1, 1 << 8, 1 << 16 - 1, 1 << 16,
            Int(Int32.max),
        ]
        for len in data {
            let extData = Data(repeating: 1, count: len)
            let msgpackElement = MsgpackElement.ext(-1, extData)
            let content = try msgpackElement.marshall()
            let (decoded, remaining) = try MsgpackElement.parse(data: content)
            XCTAssertEqual(remaining.count, 0)
            XCTAssertEqual(decoded, msgpackElement)
        }
    }

    // MARK: Convert MsgpackElement to basic Swift types
    func testDecodeUInt8() throws {
        XCTAssertEqual(
            try MsgpackElement.int(Int64(UInt8.min)).decode(type: UInt8.self),
            UInt8.min)
        XCTAssertEqual(
            try MsgpackElement.int(Int64(UInt8.max)).decode(type: UInt8.self),
            UInt8.max)
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(UInt8.max) + 1).decode(type: UInt8.self))
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(-1)).decode(type: UInt8.self))

        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(UInt8.min)).decode(type: UInt8.self),
            UInt8.min)
        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(UInt8.max)).decode(type: UInt8.self),
            UInt8.max)
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(UInt8.max) + 1).decode(type: UInt8.self)
        )
    }

    func testDecodeUInt16() throws {
        XCTAssertEqual(
            try MsgpackElement.int(Int64(UInt16.min)).decode(type: UInt16.self),
            UInt16.min)
        XCTAssertEqual(
            try MsgpackElement.int(Int64(UInt16.max)).decode(type: UInt16.self),
            UInt16.max)
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(UInt16.max) + 1).decode(type: UInt16.self)
        )
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(-1)).decode(type: UInt16.self))

        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(UInt16.min)).decode(type: UInt16.self),
            UInt16.min)
        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(UInt16.max)).decode(type: UInt16.self),
            UInt16.max)
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(UInt16.max) + 1).decode(
                type: UInt16.self))
    }

    func testDecodeUInt32() throws {
        XCTAssertEqual(
            try MsgpackElement.int(Int64(UInt32.min)).decode(type: UInt32.self),
            UInt32.min)
        XCTAssertEqual(
            try MsgpackElement.int(Int64(UInt32.max)).decode(type: UInt32.self),
            UInt32.max)
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(UInt32.max) + 1).decode(type: UInt32.self)
        )
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(-1)).decode(type: UInt32.self))

        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(UInt32.min)).decode(type: UInt32.self),
            UInt32.min)
        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(UInt32.max)).decode(type: UInt32.self),
            UInt32.max)
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(UInt32.max) + 1).decode(
                type: UInt32.self))
    }

    func testDecodeUInt64() throws {
        XCTAssertEqual(
            try MsgpackElement.int(Int64(UInt64.min)).decode(type: UInt64.self),
            UInt64.min)
        XCTAssertEqual(
            try MsgpackElement.int(Int64(Int64.max)).decode(type: UInt64.self),
            UInt64(Int64.max))
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(-1)).decode(type: UInt64.self))

        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(UInt64.min)).decode(type: UInt64.self),
            UInt64.min)
        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(UInt64.max)).decode(type: UInt64.self),
            UInt64.max)
    }

    func testDecodeInt8() throws {
        XCTAssertEqual(
            try MsgpackElement.int(Int64(Int8.min)).decode(type: Int8.self),
            Int8.min)
        XCTAssertEqual(
            try MsgpackElement.int(Int64(Int8.max)).decode(type: Int8.self),
            Int8.max)
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(Int8.max) + 1).decode(type: Int8.self))
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(Int8.min) - 1).decode(type: Int8.self))

        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(Int8.max)).decode(type: Int8.self),
            Int8.max)
        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(0)).decode(type: Int8.self), 0)
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(Int8.max) + 1).decode(type: Int8.self))
    }

    func testDecodeInt16() throws {
        XCTAssertEqual(
            try MsgpackElement.int(Int64(Int16.min)).decode(type: Int16.self),
            Int16.min)
        XCTAssertEqual(
            try MsgpackElement.int(Int64(Int16.max)).decode(type: Int16.self),
            Int16.max)
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(Int16.max) + 1).decode(type: Int16.self))
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(Int16.min) - 1).decode(type: Int16.self))

        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(0)).decode(type: Int16.self), 0)
        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(Int16.max)).decode(type: Int16.self),
            Int16.max)
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(Int16.max) + 1).decode(type: Int16.self)
        )
    }

    func testDecodeInt32() throws {
        XCTAssertEqual(
            try MsgpackElement.int(Int64(Int32.min)).decode(type: Int32.self),
            Int32.min)
        XCTAssertEqual(
            try MsgpackElement.int(Int64(Int32.max)).decode(type: Int32.self),
            Int32.max)
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(Int32.max) + 1).decode(type: Int32.self))
        XCTAssertThrowsError(
            try MsgpackElement.int(Int64(Int32.min) - 1).decode(type: Int32.self))

        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(0)).decode(type: Int32.self), 0)
        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(Int32.max)).decode(type: Int32.self),
            Int32.max)
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(Int32.max) + 1).decode(type: Int32.self)
        )
    }

    func testDecodeInt64() throws {
        XCTAssertEqual(
            try MsgpackElement.int(Int64(Int64.min)).decode(type: Int64.self),
            Int64.min)
        XCTAssertEqual(
            try MsgpackElement.int(Int64(Int64.max)).decode(type: Int64.self),
            Int64.max)

        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(0)).decode(type: Int64.self), 0)
        XCTAssertEqual(
            try MsgpackElement.uint(UInt64(Int64.max)).decode(type: Int64.self),
            Int64.max)
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(Int64.max) + 1).decode(type: Int64.self)
        )
    }

    func testDecodeBool() throws {
        XCTAssertEqual(try MsgpackElement.bool(true).decode(type: Bool.self), true)
        XCTAssertEqual(
            try MsgpackElement.bool(false).decode(type: Bool.self), false)
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(Int64.max)).decode(type: Bool.self))
    }

    func testDecodeString() throws {
        XCTAssertEqual(
            try MsgpackElement.string("abc").decode(type: String.self), "abc")
        XCTAssertEqual(try MsgpackElement.string("").decode(type: String.self), "")
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(Int64.max)).decode(type: String.self))
    }

    func testDecodeData() throws {
        XCTAssertEqual(
            try MsgpackElement.bin(Data([0x81])).decode(type: Data.self),
            Data([0x81]))
        XCTAssertEqual(
            try MsgpackElement.bin(Data()).decode(type: Data.self), Data())
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(Int64.max)).decode(type: Data.self))
    }

    func testDecodeFloat16() throws {
        let decoder = MsgpackDecoder()
        var msgpackElement = MsgpackElement.float32(Float32(1.0))
        try decoder.loadMsgpackElement(from: msgpackElement)
        var float16 = try Float16.init(from: decoder)
        XCTAssertEqual(float16, Float16(1.0))
        msgpackElement = MsgpackElement.float64(Float64(1.0))
        try decoder.loadMsgpackElement(from: msgpackElement)
        float16 = try Float16.init(from: decoder)
        XCTAssertEqual(float16, Float16(1.0))

        msgpackElement = MsgpackElement.uint(UInt64(Int64.max))
        try decoder.loadMsgpackElement(from: msgpackElement)
        XCTAssertThrowsError(try Float16.init(from: decoder))
    }

    func testDecodeFloat32() throws {
        XCTAssertEqual(
            try MsgpackElement.float32(Float32(1.0)).decode(type: Float32.self),
            Float32(1.0))
        XCTAssertEqual(
            try MsgpackElement.float64(Float64(1.0)).decode(type: Float32.self),
            Float32(1.0))
        XCTAssertEqual(
            try MsgpackElement.float64(Float64(1.1)).decode(type: Float32.self),
            Float32(1.1))
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(Int64.max)).decode(type: Float32.self))
    }

    func testDecodeFloat64() throws {
        XCTAssertEqual(
            try MsgpackElement.float32(Float32(1.0)).decode(type: Float64.self),
            Float64(1.0))
        // Lose precision. But it should not throw
        XCTAssertNotEqual(
            try MsgpackElement.float32(Float32(1.1)).decode(type: Float64.self),
            Float64(1.1))

        XCTAssertEqual(
            try MsgpackElement.float64(Float64(1.0)).decode(type: Float64.self),
            Float64(1.0))
        XCTAssertThrowsError(
            try MsgpackElement.uint(UInt64(Int64.max)).decode(type: Float64.self))
    }

    // MARK: MsgpackDecoder
    private struct Example1: Codable, Equatable {
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

    func testDecode1() throws {
        let encoder = MsgpackEncoder()
        let example = Example1()
        let encodedData = try encoder.encode(example)
        let msgpackElement = try encoder.convertToMsgpackElement()

        let decoder = MsgpackDecoder()
        try decoder.loadMsgpackElement(from: msgpackElement)
        let decodedExample1 = try Example1.init(from: decoder)

        XCTAssertEqual(example, decodedExample1)

        let decodedExample2 = try decoder.decode(
            Example1.self, from: encodedData)
        XCTAssertEqual(example, decodedExample2)
    }

    private struct Example2: Decodable {
        var Key1: Int
        var Key2: [String: String]
        var Key3: [Data]
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            self.Key1 = try container.decode(Int.self, forKey: Keys.Key1)
            self.Key2 = try container.decode(
                [String: String].self, forKey: .Key2)
            self.Key3 = try container.decode([Data].self, forKey: .Key3)
        }

        enum Keys: CodingKey {
            case Key1
            case Key2
            case Key3

            case nestedKey1
        }
    }

    func testDecode2() throws {
        var map: [String: MsgpackElement] = [:]
        map["Key1"] = MsgpackElement.int(Int64(123))
        var nestedMap: [String: MsgpackElement] = [:]
        nestedMap["nestedKey"] = MsgpackElement.string("abc")
        map["Key2"] = MsgpackElement.map(nestedMap)
        let array: [MsgpackElement] = [MsgpackElement.bin(Data([0xab]))]
        map["Key3"] = MsgpackElement.array(array)
        map["Key4"] = MsgpackElement.null

        let msgpackElement = MsgpackElement.map(map)
        let decoder = MsgpackDecoder()
        try decoder.loadMsgpackElement(from: msgpackElement)
        let decodedExample = try Example2.init(from: decoder)
        XCTAssertEqual(decodedExample.Key1, 123)
        let expectedMap: [String: String] = ["nestedKey": "abc"]
        XCTAssertEqual(decodedExample.Key2, expectedMap)
        XCTAssertEqual(decodedExample.Key3, [Data([0xab])])
    }

    private class BaseClassExample: Codable {
        var parent: String = "123"
    }

    private class InherienceWithSameContainerExample: BaseClassExample {
        var child: String = "456"

        override init() {
            super.init()
        }

        override func encode(to encoder: any Encoder) throws {
            try super.encode(to: encoder)
            // Switching to a KeyedContainer with different key type
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(child, forKey: .child)
        }

        required init(from decoder: any Decoder) throws {
            try super.init(from: decoder)
            let container = try decoder.container(keyedBy: Keys.self)
            self.child = try container.decode(String.self, forKey: .child)
        }

        enum Keys: CodingKey {
            case child
        }
    }

    func testInherienceUsingSameTopContainer() throws {  // Undocumented behavior. Keep aligh with the jsonEncoder
        let encoder = MsgpackEncoder()
        let example = InherienceWithSameContainerExample()
        example.parent = "abc"
        example.child = "def"
        let data = try encoder.encode(example)
        let msgpackElement = try encoder.convertToMsgpackElement()
        let decoder = MsgpackDecoder()
        try decoder.loadMsgpackElement(from: msgpackElement)
        let decodedExample = try InherienceWithSameContainerExample.init(
            from: decoder)
        XCTAssertEqual(decodedExample.parent, "abc")
        XCTAssertEqual(decodedExample.child, "def")
        let decodedExample2 = try decoder.decode(
            InherienceWithSameContainerExample.self, from: data)
        XCTAssertEqual(decodedExample2.parent, "abc")
        XCTAssertEqual(decodedExample2.child, "def")
    }

    private class KeyedSuperExample: BaseClassExample {
        var child: String = ""

        override init() {
            super.init()
        }
        override func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(child, forKey: .child)
            let encoder = container.superEncoder()
            try super.encode(to: encoder)
        }

        required init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            self.child = try container.decode(String.self, forKey: .child)
            let superDecoder = try container.superDecoder()
            try super.init(from: superDecoder)
        }

        enum Keys: CodingKey {
            case child
        }
    }

    func testKeyedInherience() throws {
        let encoder = MsgpackEncoder()
        let example = KeyedSuperExample()
        example.parent = "abc"
        example.child = "def"
        let data = try encoder.encode(example)
        let msgpackElement = try encoder.convertToMsgpackElement()
        let decoder = MsgpackDecoder()
        try decoder.loadMsgpackElement(from: msgpackElement)
        let decodedExample = try KeyedSuperExample.init(from: decoder)
        XCTAssertEqual(decodedExample.parent, "abc")
        XCTAssertEqual(decodedExample.child, "def")
        let decodedExample2 = try decoder.decode(
            KeyedSuperExample.self, from: data)
        XCTAssertEqual(decodedExample2.parent, "abc")
        XCTAssertEqual(decodedExample2.child, "def")
    }

    // MARK: Extension
    func testDecodeTimestamp() throws {
        let data: [Double] = [
            0, -0.5, -1.5, 1.5, Double(UInt32.max), Double(UInt32.max) + 1,
            Double(UInt64(1) << 34 - 1), Double(UInt64(1) << 34),
        ]
        for time in data {
            let seconds = Int64(time.rounded(FloatingPointRoundingRule.down))
            let nanoseconds = UInt32(
                ((time - Double(seconds)) * 1_000_000_000).rounded(
                    FloatingPointRoundingRule.down))
            let timestamp = MsgpackTimestamp(
                seconds: seconds, nanoseconds: nanoseconds)
            let encoder = MsgpackEncoder()
            let content = try encoder.encode(timestamp)
            let decoder = MsgpackDecoder()
            let timestamp2 = try decoder.decode(
                MsgpackTimestamp.self, from: content)
            XCTAssertEqual(timestamp, timestamp2)
        }
    }

    // MARK: User Info
    struct UserInfoExample: Codable {
        init() {
        }

        func encode(to encoder: any Encoder) throws {
            var container1 = encoder.container(keyedBy: Keys.self)
            let superEncoder = container1.superEncoder()
            _ = superEncoder.singleValueContainer()
            let superEncoder2 = container1.superEncoder(forKey: .Key1)
            var container3 = superEncoder2.unkeyedContainer()
            let superEncoder3 = container3.superEncoder()
            _ = superEncoder3.singleValueContainer()
        }

        init(from decoder: any Decoder) throws {
            AsserUserInfo(decoder.userInfo)
            let container1 = try decoder.container(keyedBy: Keys.self)
            let superDecoder = try container1.superDecoder()
            AsserUserInfo(superDecoder.userInfo)
            _ = try superDecoder.singleValueContainer()
            let superDecoder2 = try container1.superDecoder(forKey: .Key1)
            AsserUserInfo(superDecoder2.userInfo)
            var container3 = try superDecoder2.unkeyedContainer()
            let superDecoder3 = try container3.superDecoder()
            AsserUserInfo(superDecoder3.userInfo)
            _ = try superDecoder3.singleValueContainer()
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
        let encoder = MsgpackEncoder(userInfo: userInfo)
        let example = UserInfoExample()
        let data = try encoder.encode(example)
        let decoder = MsgpackDecoder(userInfo: userInfo)
        _ = try decoder.decode(UserInfoExample.self, from: data)
    }

    struct CodingKeyExample: Codable {
        init() {
        }

        func encode(to encoder: any Encoder) throws {
            var container1 = encoder.container(keyedBy: Keys.self)
            let superEncoder = container1.superEncoder()
            _ = superEncoder.singleValueContainer()
            let superEncoder2 = container1.superEncoder(forKey: .superKey)
            _ = superEncoder2.singleValueContainer()
            var container2 = container1.nestedContainer(
                keyedBy: Keys.self, forKey: .Key1)
            var container3 = container2.nestedUnkeyedContainer(forKey: .Key2)
            _ = container3.nestedUnkeyedContainer()
        }

        init(from decoder: any Decoder) throws {
            XCTAssertEqual(decoder.codingPath.count, 0)
            let container1 = try decoder.container(keyedBy: Keys.self)
            XCTAssertEqual(container1.codingPath.count, 0)

            let superDecoder = try container1.superDecoder()
            XCTAssertEqual(superDecoder.codingPath.count, 1)
            XCTAssertEqual(
                superDecoder.codingPath[0] as! MsgpackCodingKey,
                MsgpackCodingKey(stringValue: "super"))

            let superSingleValueContainer =
                try superDecoder.singleValueContainer()
            XCTAssertEqual(superSingleValueContainer.codingPath.count, 1)
            XCTAssertEqual(
                superSingleValueContainer.codingPath[0] as! MsgpackCodingKey,
                MsgpackCodingKey(stringValue: "super"))

            let superDecoder2 = try container1.superDecoder(forKey: .superKey)
            XCTAssertEqual(superDecoder2.codingPath.count, 1)
            XCTAssertEqual(superDecoder2.codingPath[0] as! Keys, Keys.superKey)

            let superSingleValueContainer2 =
                try superDecoder2.singleValueContainer()
            XCTAssertEqual(superSingleValueContainer2.codingPath.count, 1)
            XCTAssertEqual(
                superSingleValueContainer2.codingPath[0] as! Keys, Keys.superKey
            )

            let container2 = try container1.nestedContainer(
                keyedBy: Keys.self, forKey: .Key1)
            XCTAssertEqual(container2.codingPath.count, 1)
            XCTAssertEqual(container2.codingPath[0] as! Keys, Keys.Key1)

            var container3 = try container2.nestedUnkeyedContainer(
                forKey: .Key2)
            XCTAssertEqual(container3.codingPath.count, 2)
            XCTAssertEqual(container3.codingPath[0] as! Keys, Keys.Key1)
            XCTAssertEqual(container3.codingPath[1] as! Keys, Keys.Key2)

            let container4 = try container3.nestedUnkeyedContainer()
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
        let data = try encoder.encode(example)

        let decoder = MsgpackDecoder()
        _ = try decoder.decode(CodingKeyExample.self, from: data)
    }

    // MARK: Container properties
    struct UnkeyedContainerCountExample: Codable {
        init() {
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(true)
            _ = container.superEncoder().singleValueContainer()
        }
        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            XCTAssertEqual(container.count, 2)
            XCTAssertEqual(container.currentIndex, 0)
            XCTAssertEqual(container.isAtEnd, false)
            XCTAssertEqual(try container.decodeNil(), false)
            XCTAssertEqual(container.count, 2)
            XCTAssertEqual(container.currentIndex, 0)
            XCTAssertEqual(container.isAtEnd, false)
            let bool = try container.decode(Bool.self)
            XCTAssertEqual(bool, true)
            XCTAssertEqual(container.count, 2)
            XCTAssertEqual(container.currentIndex, 1)
            XCTAssertEqual(container.isAtEnd, false)
            _ = try container.superDecoder().singleValueContainer()
            XCTAssertEqual(container.count, 2)
            XCTAssertEqual(container.currentIndex, 2)
            XCTAssertEqual(container.isAtEnd, true)
        }
    }

    func testUnkeyedContainerCount() throws {
        let example = UnkeyedContainerCountExample()
        let encoder = MsgpackEncoder()
        let data = try encoder.encode(example)

        let decoder = MsgpackDecoder()
        _ = try decoder.decode(UnkeyedContainerCountExample.self, from: data)
    }

    struct KeyedContainerExample: Codable {
        init() {
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(true, forKey: .Key1)
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            XCTAssertEqual(container.contains(.Key1), true)
            XCTAssertEqual(container.contains(.Key2), false)
            XCTAssertEqual(container.allKeys.count, 1)
            XCTAssertEqual(container.allKeys[0], .Key1)
        }

        enum Keys: CodingKey {
            case Key1, Key2
        }
    }

    func testKeyedContainerKeys() throws {
        let encoder = MsgpackEncoder()
        let example = KeyedContainerExample()
        let data = try encoder.encode(example)
        let decoder = MsgpackDecoder()
        _ = try decoder.decode(KeyedContainerExample.self, from: data)
    }
}
