import Foundation

/// Valve's text KeyValues format. Duplicate keys are retained (library files can repeat them).
struct VDFNode: Sendable {
    var entries: [(key: String, value: VDFValue)] = []
    func string(_ key: String) -> String? {
        entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value.string
    }
    func node(_ key: String) -> VDFNode? {
        entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value.node
    }
    func path(_ keys: String...) -> VDFNode? {
        keys.reduce(Optional(self)) { $0?.node($1) }
    }
}
indirect enum VDFValue: Sendable {
    case string(String), object(VDFNode)
    var string: String? { if case .string(let value) = self { return value }; return nil }
    var node: VDFNode? { if case .object(let value) = self { return value }; return nil }
}
struct VDFParser {
    enum ParseError: Error { case malformed, tooDeep }
    private var characters: [Character]
    private var cursor = 0
    init(_ text: String) { characters = Array(text) }
    static func read(_ url: URL) throws -> VDFNode {
        var parser = VDFParser(try String(contentsOf: url, encoding: .utf8))
        return try parser.parse()
    }
    mutating func parse() throws -> VDFNode { try object(nested: false, depth: 0) }
    private mutating func object(nested: Bool, depth: Int) throws -> VDFNode {
        guard depth < 64 else { throw ParseError.tooDeep }
        var result = VDFNode()
        while let key = try token() {
            if key == "}" { guard nested else { throw ParseError.malformed }; return result }
            guard key != "{", let value = try token(), value != "}" else { throw ParseError.malformed }
            if value == "{" { result.entries.append((key, .object(try object(nested: true, depth: depth + 1)))) }
            else { result.entries.append((key, .string(value))) }
        }
        if nested { throw ParseError.malformed }
        return result
    }
    private mutating func token() throws -> String? {
        while cursor < characters.count {
            if characters[cursor].isWhitespace || characters[cursor] == "\u{FEFF}" { cursor += 1; continue }
            if characters[cursor] == "/", cursor + 1 < characters.count, characters[cursor + 1] == "/" {
                while cursor < characters.count, characters[cursor] != "\n" { cursor += 1 }; continue
            }
            break
        }
        guard cursor < characters.count else { return nil }
        let current = characters[cursor]; cursor += 1
        if current == "{" || current == "}" { return String(current) }
        if current == "\"" {
            var value = ""
            while cursor < characters.count {
                let char = characters[cursor]; cursor += 1
                if char == "\"" { return value }
                if char == "\\", cursor < characters.count {
                    let next = characters[cursor]
                    if next == "\"" || next == "\\" { value.append(next); cursor += 1 }
                    else if next == "n" { value.append("\n"); cursor += 1 }
                    else if next == "t" { value.append("\t"); cursor += 1 }
                    else { value.append(char) }
                } else { value.append(char) }
            }
            throw ParseError.malformed
        }
        var value = String(current)
        while cursor < characters.count, !characters[cursor].isWhitespace, characters[cursor] != "{", characters[cursor] != "}" {
            value.append(characters[cursor]); cursor += 1
        }
        return value
    }
}
