import Foundation

/// JSON that keeps object key order and number spelling, for editing a file someone else owns
/// (Claude Code's `settings.json`) without reordering or reformatting what we did not touch.
/// `JSONSerialization` loses key order and prints `"key" : value`, so every line would change.
indirect enum OrderedJSON: Equatable, Sendable {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// The literal as written, so `1.0` and `1e3` survive a round trip.
    case number(String)
    case bool(Bool)
    case null

    static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(a), .array(b)): a == b
        case let (.string(a), .string(b)): a == b
        case let (.number(a), .number(b)): a == b
        case let (.bool(a), .bool(b)): a == b
        case (.null, .null): true
        default: false
        }
    }

    struct ParseError: Error, Equatable {
        let offset: Int
    }

    // MARK: Access

    subscript(key: String) -> OrderedJSON? {
        guard case .object(let members) = self else { return nil }
        return members.last(where: { $0.key == key })?.value
    }

    /// Replaces the member in place (keeping its position) or appends it; nil removes it.
    /// Duplicate keys collapse into the first one.
    mutating func set(_ key: String, _ value: OrderedJSON?) {
        guard case .object(var members) = self else { return }
        let first = members.firstIndex { $0.key == key }
        // Only later duplicates go, so `first` still points at the same member.
        members = members.enumerated().filter { $0.offset == first || $0.element.key != key }.map(\.element)
        switch (first, value) {
        case let (index?, value?): members[index].value = value
        case let (index?, nil): members.remove(at: index)
        case let (nil, value?): members.append((key, value))
        case (nil, nil): break
        }
        self = .object(members)
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var arrayValue: [OrderedJSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    // MARK: Parse

    init(parsing data: Data) throws {
        var parser = Parser(bytes: Array(data))
        parser.skipWhitespace()
        self = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw ParseError(offset: parser.index) }
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        /// Settings files are shallow; the bound keeps hostile input from exhausting the stack.
        static let maxDepth = 256

        init(bytes: [UInt8]) {
            // A UTF-8 BOM is not JSON, but editors write one.
            self.bytes = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(bytes.dropFirst(3)) : bytes
        }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        func fail() -> ParseError { ParseError(offset: index) }

        mutating func expect(_ literal: String) throws {
            let utf8 = Array(literal.utf8)
            guard index + utf8.count <= bytes.count, Array(bytes[index..<index + utf8.count]) == utf8 else { throw fail() }
            index += utf8.count
        }

        mutating func value(depth: Int) throws -> OrderedJSON {
            guard depth < Self.maxDepth, index < bytes.count else { throw fail() }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func object(depth: Int) throws -> OrderedJSON {
            index += 1
            var members: [(key: String, value: OrderedJSON)] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw fail() }
                let key = try string()
                skipWhitespace()
                try expect(":")
                skipWhitespace()
                members.append((key, try value(depth: depth + 1)))
                skipWhitespace()
                guard index < bytes.count else { throw fail() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                throw fail()
            }
        }

        mutating func array(depth: Int) throws -> OrderedJSON {
            index += 1
            var items: [OrderedJSON] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                skipWhitespace()
                items.append(try value(depth: depth + 1))
                skipWhitespace()
                guard index < bytes.count else { throw fail() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw fail()
            }
        }

        mutating func string() throws -> String {
            index += 1
            var out = [UInt8]()
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                switch byte {
                case UInt8(ascii: "\""):
                    guard let s = String(bytes: out, encoding: .utf8) else { throw fail() }
                    return s
                case UInt8(ascii: "\\"):
                    guard index < bytes.count else { throw fail() }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""): out.append(0x22)
                    case UInt8(ascii: "\\"): out.append(0x5C)
                    case UInt8(ascii: "/"): out.append(0x2F)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        var code = try hex4()
                        if (0xD800..<0xDC00).contains(code) {
                            // A high surrogate must be followed by `\uDC00`–`\uDFFF`.
                            try expect("\\u")
                            let low = try hex4()
                            guard (0xDC00..<0xE000).contains(low) else { throw fail() }
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        guard let scalar = Unicode.Scalar(code) else { throw fail() }
                        out.append(contentsOf: Array(String(Character(scalar)).utf8))
                    default: throw fail()
                    }
                default:
                    guard byte >= 0x20 else { throw fail() }
                    out.append(byte)
                }
            }
            throw fail()
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count,
                  let code = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16)
            else { throw fail() }
            index += 4
            return code
        }

        mutating func number() throws -> String {
            let start = index
            func digits() -> Int {
                let s = index
                while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
                return index - s
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
            let intStart = index
            guard digits() > 0 else { throw fail() }
            if bytes[intStart] == UInt8(ascii: "0"), index - intStart > 1 { throw ParseError(offset: intStart) }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard digits() > 0 else { throw fail() }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                guard digits() > 0 else { throw fail() }
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }
    }

    // MARK: Serialize

    /// Two-space indent and `"key": value`, the layout Claude Code itself writes. Empty containers
    /// stay on one line. Non-ASCII text is written as is, not `\u` escaped.
    func serialized() -> String {
        var out = ""
        write(into: &out, indent: 0)
        return out + "\n"
    }

    private func write(into out: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent + 1)
        let closePad = String(repeating: "  ", count: indent)
        switch self {
        case .object(let members):
            guard !members.isEmpty else { out += "{}"; return }
            out += "{\n"
            for (i, member) in members.enumerated() {
                out += pad + Self.quoted(member.key) + ": "
                member.value.write(into: &out, indent: indent + 1)
                out += i == members.count - 1 ? "\n" : ",\n"
            }
            out += closePad + "}"
        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += pad
                item.write(into: &out, indent: indent + 1)
                out += i == items.count - 1 ? "\n" : ",\n"
            }
            out += closePad + "]"
        case .string(let s): out += Self.quoted(s)
        case .number(let n): out += n
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
