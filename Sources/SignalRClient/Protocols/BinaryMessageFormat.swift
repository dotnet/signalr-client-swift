import Foundation

// TODO: Move messagepack to a separate package
class BinaryMessageFormat {
    private static let MessageSize2GB: Int = 1 << 31

    static func parse(_ data: Data) throws -> [Data] {
        var messages: [Data] = []
        var index = 0

        while index < data.count {
            var number: UInt64 = 0
            var numberBytes = 0
            while numberBytes <= 5 {
                guard index < data.count else {
                    throw SignalRError.incompleteMessage
                }
                let byte: UInt64 = UInt64(data[index])
                number = number | (byte & 0x7f) << (7 * numberBytes)
                numberBytes += 1
                index += 1
                if byte & 0x80 == 0 {
                    break
                }
            }
            guard numberBytes <= 5 else {
                throw SignalRError.invalidData("Invalid message size")
            }
            guard number <= MessageSize2GB else {
                throw SignalRError.messageBiggerThan2GB
            }
            guard number > 0 else {
                continue
            }
            if index + Int(number) > data.count {
                throw SignalRError.incompleteMessage
            }
            let message = data.subdata(in: index ..< (index + Int(number)))
            messages.append(message)
            index += Int(number)
        }
        return messages
    }

    static func write(_ data: Data) throws -> Data {
        var number = data.count
        guard number <= MessageSize2GB else {
            throw SignalRError.messageBiggerThan2GB
        }
        var bytes: [UInt8] = []
        repeat {
            var byte = (UInt8)(number & 0x7f)
            number >>= 7
            if number > 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while number > 0
        return Data(bytes) + data
    }
}
