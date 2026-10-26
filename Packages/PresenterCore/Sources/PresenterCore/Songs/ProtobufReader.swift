import Foundation

/// Reads Protocol Buffers' wire format without a schema: enough to pull fields out of a ProPresenter file by number.
/// Nested messages are read when asked for.
struct ProtobufMessage {
    enum Value {
        case varint(UInt64)
        case bytes(Data)
        case fixed32(UInt32)
        case fixed64(UInt64)
    }

    struct Malformed: Error {}

    private(set) var fields: [(number: Int, value: Value)] = []

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        var index = 0

        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard index < bytes.count, shift < 64 else { throw Malformed() }
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
        }

        func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, index + count <= bytes.count else { throw Malformed() }
            defer { index += count }
            return bytes[index..<(index + count)]
        }

        while index < bytes.count {
            let key = try varint()
            let number = Int(key >> 3)
            guard number > 0 else { throw Malformed() }
            switch key & 7 {
            case 0:
                fields.append((number, .varint(try varint())))
            case 1:
                let raw = try take(8)
                fields.append((number, .fixed64(raw.reversed().reduce(0) { $0 << 8 | UInt64($1) })))
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count) else { throw Malformed() }
                fields.append((number, .bytes(Data(try take(Int(length))))))
            case 5:
                let raw = try take(4)
                fields.append((number, .fixed32(raw.reversed().reduce(0) { $0 << 8 | UInt32($1) })))
            default:
                // Groups (3, 4) are long deprecated; anything else isn't protobuf.
                throw Malformed()
            }
        }
    }

    func bytes(_ number: Int) -> Data? {
        for field in fields where field.number == number {
            if case .bytes(let data) = field.value { return data }
        }
        return nil
    }

    func string(_ number: Int) -> String? {
        bytes(number).flatMap { String(data: $0, encoding: .utf8) }
    }

    func varint(_ number: Int) -> UInt64? {
        for field in fields where field.number == number {
            if case .varint(let value) = field.value { return value }
        }
        return nil
    }

    func message(_ number: Int) -> ProtobufMessage? {
        bytes(number).flatMap { try? ProtobufMessage($0) }
    }

    /// Every message in a repeated field, in order. Ones that don't read are left out.
    func messages(_ number: Int) -> [ProtobufMessage] {
        fields.compactMap { field in
            guard field.number == number, case .bytes(let data) = field.value else { return nil }
            return try? ProtobufMessage(data)
        }
    }
}
