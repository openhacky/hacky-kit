import Foundation

/// Canonical Hacky Core v0.1 JSON encoder.
///
/// Output is compact UTF-8 in fixed `hacky`, `name`, `turns`, `instructions`
/// order, with no BOM and exactly one terminal LF.
public enum HackyJSONEncoder {
    public static func encode(_ document: HackyDocument) throws -> Data {
        let issues = HackyValidator.issues(for: document)
        guard issues.isEmpty else { throw HackyValidationFailure(issues: issues) }
        let data = try encodeUnchecked(document)
        guard data.count <= HackyValidator.maximumByteCount else {
            throw HackyValidationFailure(issues: [
                HackyValidationIssue(
                    code: .tooLarge,
                    message: "Canonical JSON exceeds \(HackyValidator.maximumByteCount) bytes."
                )
            ])
        }
        return data
    }

    public static func string(_ document: HackyDocument) throws -> String {
        String(decoding: try encode(document), as: UTF8.self)
    }

    static func encodeUnchecked(_ document: HackyDocument) throws -> Data {
        let text = "{\"hacky\":\(quote(document.hacky)),\"name\":\(quote(document.name)),\"turns\":\(document.turns),\"instructions\":\(quote(document.instructions))}\n"
        guard let data = text.data(using: .utf8) else {
            throw HackyValidationFailure(issues: [
                HackyValidationIssue(code: .invalidUTF8, message: "Could not encode canonical UTF-8.")
            ])
        }
        return data
    }

    private static func quote(_ value: String) -> String {
        var output = "\""
        output.reserveCapacity(value.utf8.count + 2)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: output += "\\\""
            case 0x5C: output += "\\\\"
            case 0x08: output += "\\b"
            case 0x09: output += "\\t"
            case 0x0A: output += "\\n"
            case 0x0C: output += "\\f"
            case 0x0D: output += "\\r"
            case 0x00...0x1F, 0x7F:
                output += String(format: "\\u%04X", scalar.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
        return output
    }
}

/// Byte-level and semantic Hacky Core v0.1 validation.
public enum HackyValidator {
    public static let maximumByteCount = 32 * 1_024
    public static let maximumNameLength = 80
    public static let maximumInstructionsLength = 8_192
    public static let validKeys: Set<String> = ["hacky", "name", "turns", "instructions"]

    /// Validates raw UTF-8 and returns a document only when every v0.1 rule passes.
    public static func validate(_ data: Data, requireCanonical: Bool = true) -> HackyValidationResult {
        var found: [HackyValidationIssue] = []
        guard !data.isEmpty else {
            return HackyValidationResult(document: nil, issues: [
                HackyValidationIssue(code: .emptyInput, message: "Input is empty.")
            ])
        }
        if data.count > maximumByteCount {
            return HackyValidationResult(document: nil, issues: [
                HackyValidationIssue(
                    code: .tooLarge,
                    message: "Input exceeds \(maximumByteCount) bytes."
                )
            ])
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            found.append(HackyValidationIssue(code: .byteOrderMark, message: "UTF-8 BOM is forbidden."))
        }
        guard let source = String(data: data, encoding: .utf8) else {
            found.append(HackyValidationIssue(code: .invalidUTF8, message: "Input is not valid UTF-8."))
            return HackyValidationResult(document: nil, issues: found)
        }

        let object: [String: StrictJSONValue]
        do {
            object = try StrictJSONParser(source).parseObject()
        } catch let error as StrictJSONError {
            found.append(HackyValidationIssue(
                code: error.isDuplicateKey ? .duplicateKey : .invalidJSON,
                path: error.path,
                message: error.message
            ))
            return HackyValidationResult(document: nil, issues: found)
        } catch {
            found.append(HackyValidationIssue(code: .invalidJSON, message: "Input is not a JSON object."))
            return HackyValidationResult(document: nil, issues: found)
        }

        for key in object.keys.sorted() where !validKeys.contains(key) {
            found.append(HackyValidationIssue(code: .unknownKey, path: "$.\(key)", message: "Unknown key \(key)."))
        }
        for key in validKeys.sorted() where object[key] == nil {
            found.append(HackyValidationIssue(code: .missingKey, path: "$.\(key)", message: "Required key \(key) is missing."))
        }

        let version = stringValue(object["hacky"], path: "$.hacky", found: &found)
        let name = stringValue(object["name"], path: "$.name", found: &found)
        let turns = integerValue(object["turns"], path: "$.turns", found: &found)
        let instructions = stringValue(object["instructions"], path: "$.instructions", found: &found)
        guard let version, let name, let turns, let instructions else {
            return HackyValidationResult(document: nil, issues: found)
        }

        let candidate = HackyDocument(
            uncheckedHacky: version,
            name: name,
            turns: turns,
            instructions: instructions
        )
        found.append(contentsOf: issues(for: candidate))
        if requireCanonical, found.isEmpty,
           let canonical = try? HackyJSONEncoder.encodeUnchecked(candidate), canonical != data {
            found.append(HackyValidationIssue(
                code: .nonCanonical,
                message: "JSON is valid but not in the canonical byte representation."
            ))
        }
        let unique = deduplicated(found)
        return HackyValidationResult(document: unique.isEmpty ? candidate : nil, issues: unique)
    }

    public static func decode(_ data: Data, requireCanonical: Bool = true) throws -> HackyDocument {
        let result = validate(data, requireCanonical: requireCanonical)
        guard let document = result.document else {
            throw HackyValidationFailure(issues: result.issues)
        }
        return document
    }

    public static func issues(for document: HackyDocument) -> [HackyValidationIssue] {
        var found: [HackyValidationIssue] = []
        if document.hacky != HackyDocument.version {
            found.append(HackyValidationIssue(
                code: .wrongVersion,
                path: "$.hacky",
                message: "hacky must equal \"0.1\"."
            ))
        }
        validateString(
            document.name,
            path: "$.name",
            minimum: 1,
            maximum: maximumNameLength,
            allowLF: false,
            found: &found
        )
        if document.name.contains(HackyActivationV01.activationMarker)
            || document.name.contains(HackyActivationV01.effectMarker) {
            found.append(HackyValidationIssue(
                code: .reservedMarker,
                path: "$.name",
                message: "name may not contain a reserved Hacky marker."
            ))
        }
        if !(1...99).contains(document.turns) {
            found.append(HackyValidationIssue(
                code: .turnsOutOfRange,
                path: "$.turns",
                message: "turns must be an integer from 1 through 99."
            ))
        }
        validateString(
            document.instructions,
            path: "$.instructions",
            minimum: 1,
            maximum: maximumInstructionsLength,
            allowLF: true,
            found: &found
        )
        if let parsed = HackyActivationV01.parsedEffect(
            from: document.instructions,
            name: document.name,
            turns: document.turns
        ) {
            found.append(contentsOf: sourceIssues(
                name: document.name,
                turns: document.turns,
                effect: parsed.effect
            ).filter { $0.path == "effect" })
        } else {
            found.append(HackyValidationIssue(
                code: .invalidActivation,
                path: "$.instructions",
                message: "instructions must contain an exact fixed Hacky v0.1 activation followed by one effect."
            ))
        }
        if let data = try? HackyJSONEncoder.encodeUnchecked(document), data.count > maximumByteCount {
            found.append(HackyValidationIssue(
                code: .tooLarge,
                message: "Canonical JSON exceeds \(maximumByteCount) bytes."
            ))
        }
        return deduplicated(found)
    }

    static func sourceIssues(name: String, turns: Int, effect: String) -> [HackyValidationIssue] {
        var found: [HackyValidationIssue] = []
        validateString(
            name,
            path: "$.name",
            minimum: 1,
            maximum: maximumNameLength,
            allowLF: false,
            found: &found
        )
        if name.contains(HackyActivationV01.activationMarker)
            || name.contains(HackyActivationV01.effectMarker) {
            found.append(HackyValidationIssue(
                code: .reservedMarker,
                path: "$.name",
                message: "name may not contain a reserved Hacky marker."
            ))
        }
        if !(1...99).contains(turns) {
            found.append(HackyValidationIssue(
                code: .turnsOutOfRange,
                path: "$.turns",
                message: "turns must be an integer from 1 through 99."
            ))
        }
        validateString(
            effect,
            path: "effect",
            minimum: 1,
            maximum: maximumInstructionsLength,
            allowLF: true,
            found: &found
        )
        if effect.contains(HackyActivationV01.activationMarker)
            || effect.contains(HackyActivationV01.effectMarker) {
            found.append(HackyValidationIssue(
                code: .reservedMarker,
                path: "effect",
                message: "The effect may not contain a reserved Hacky marker."
            ))
        }
        return deduplicated(found)
    }

    private static func validateString(
        _ value: String,
        path: String,
        minimum: Int,
        maximum: Int,
        allowLF: Bool,
        found: inout [HackyValidationIssue]
    ) {
        let normalized = value.precomposedStringWithCanonicalMapping
        if Array(value.unicodeScalars) != Array(normalized.unicodeScalars) {
            found.append(HackyValidationIssue(code: .notNFC, path: path, message: "String must be NFC-normalized."))
        }
        if value != value.trimmingCharacters(in: .whitespacesAndNewlines) {
            found.append(HackyValidationIssue(
                code: .surroundingWhitespace,
                path: path,
                message: "Leading or trailing whitespace is forbidden."
            ))
        }
        let count = value.unicodeScalars.count
        if !(minimum...maximum).contains(count) {
            found.append(HackyValidationIssue(
                code: .lengthOutOfRange,
                path: path,
                message: "String length must be \(minimum)...\(maximum) Unicode scalar values."
            ))
        }
        let forbidden = value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0A: !allowLF
            case 0x00...0x1F, 0x7F...0x9F: true
            default: false
            }
        }
        if forbidden {
            found.append(HackyValidationIssue(
                code: .disallowedControl,
                path: path,
                message: "String contains a disallowed control character."
            ))
        }
    }

    private static func stringValue(
        _ value: StrictJSONValue?,
        path: String,
        found: inout [HackyValidationIssue]
    ) -> String? {
        guard let value else { return nil }
        guard case .string(let string) = value else {
            found.append(HackyValidationIssue(code: .wrongType, path: path, message: "Value must be a string."))
            return nil
        }
        return string
    }

    private static func integerValue(
        _ value: StrictJSONValue?,
        path: String,
        found: inout [HackyValidationIssue]
    ) -> Int? {
        guard let value else { return nil }
        guard case .integer(let integer) = value else {
            found.append(HackyValidationIssue(code: .wrongType, path: path, message: "Value must be an integer."))
            return nil
        }
        return integer
    }

    private static func deduplicated(_ values: [HackyValidationIssue]) -> [HackyValidationIssue] {
        var seen: Set<String> = []
        return values.filter {
            seen.insert("\($0.code.rawValue)\u{0}\($0.path)\u{0}\($0.message)").inserted
        }
    }
}

private enum StrictJSONValue {
    case string(String)
    case integer(Int)
    case unsupported
}

private struct StrictJSONError: Error {
    let path: String
    let message: String
    let isDuplicateKey: Bool
}

private final class StrictJSONParser {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ source: String) {
        scalars = Array(source.unicodeScalars)
    }

    func parseObject() throws -> [String: StrictJSONValue] {
        skipWhitespace()
        guard take(Unicode.Scalar(0x7B)!) else { throw error("Top-level JSON must be an object.") }
        skipWhitespace()
        var result: [String: StrictJSONValue] = [:]
        if take(Unicode.Scalar(0x7D)!) {
            skipWhitespace()
            guard atEnd else { throw error("Trailing content after JSON object.") }
            return result
        }
        while true {
            skipWhitespace()
            let key = try parseString()
            guard result[key] == nil else {
                throw StrictJSONError(path: "$.\(key)", message: "Duplicate key \(key).", isDuplicateKey: true)
            }
            skipWhitespace()
            guard take(Unicode.Scalar(0x3A)!) else { throw error("Expected colon after object key.") }
            skipWhitespace()
            result[key] = try parseValue()
            skipWhitespace()
            if take(Unicode.Scalar(0x7D)!) { break }
            guard take(Unicode.Scalar(0x2C)!) else { throw error("Expected comma or closing brace.") }
        }
        skipWhitespace()
        guard atEnd else { throw error("Trailing content after JSON object.") }
        return result
    }

    private func parseValue() throws -> StrictJSONValue {
        guard let scalar = peek else { throw error("Missing JSON value.") }
        if scalar.value == 0x22 { return .string(try parseString()) }
        if scalar.value == 0x2D || (0x30...0x39).contains(scalar.value) {
            return .integer(try parseInteger())
        }
        try skipUnsupportedValue()
        return .unsupported
    }

    private func parseString() throws -> String {
        guard take(Unicode.Scalar(0x22)!) else { throw error("Expected JSON string.") }
        var output = ""
        while let scalar = peek {
            index += 1
            if scalar.value == 0x22 { return output }
            if scalar.value == 0x5C {
                guard let escaped = peek else { throw error("Unterminated escape sequence.") }
                index += 1
                switch escaped.value {
                case 0x22: output.append("\"")
                case 0x5C: output.append("\\")
                case 0x2F: output.append("/")
                case 0x62: output.append("\u{0008}")
                case 0x66: output.append("\u{000C}")
                case 0x6E: output.append("\n")
                case 0x72: output.append("\r")
                case 0x74: output.append("\t")
                case 0x75:
                    let first = try parseHexQuad()
                    if (0xD800...0xDBFF).contains(first) {
                        guard take(Unicode.Scalar(0x5C)!), take(Unicode.Scalar(0x75)!) else {
                            throw error("High surrogate must be followed by a low surrogate.")
                        }
                        let second = try parseHexQuad()
                        guard (0xDC00...0xDFFF).contains(second) else {
                            throw error("Invalid low surrogate.")
                        }
                        let value = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                        guard let decoded = Unicode.Scalar(value) else { throw error("Invalid Unicode escape.") }
                        output.unicodeScalars.append(decoded)
                    } else {
                        guard !(0xDC00...0xDFFF).contains(first), let decoded = Unicode.Scalar(first) else {
                            throw error("Invalid Unicode escape.")
                        }
                        output.unicodeScalars.append(decoded)
                    }
                default: throw error("Invalid JSON escape sequence.")
                }
            } else {
                guard scalar.value >= 0x20 else { throw error("Unescaped control character in JSON string.") }
                output.unicodeScalars.append(scalar)
            }
        }
        throw error("Unterminated JSON string.")
    }

    private func parseInteger() throws -> Int {
        let start = index
        _ = take(Unicode.Scalar(0x2D)!)
        guard let first = peek, (0x30...0x39).contains(first.value) else { throw error("Invalid number.") }
        if first.value == 0x30 {
            index += 1
            if let next = peek, (0x30...0x39).contains(next.value) { throw error("Leading zero in number.") }
        } else {
            while let next = peek, (0x30...0x39).contains(next.value) { index += 1 }
        }
        if let next = peek, next.value == 0x2E || next.value == 0x65 || next.value == 0x45 {
            throw error("turns must use integer syntax.")
        }
        let raw = String(String.UnicodeScalarView(scalars[start..<index]))
        guard let value = Int(raw) else { throw error("Integer is outside the supported range.") }
        return value
    }

    private func parseHexQuad() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let scalar = peek else { throw error("Truncated Unicode escape.") }
            index += 1
            let digit: UInt32
            switch scalar.value {
            case 0x30...0x39: digit = scalar.value - 0x30
            case 0x41...0x46: digit = scalar.value - 0x41 + 10
            case 0x61...0x66: digit = scalar.value - 0x61 + 10
            default: throw error("Invalid hexadecimal digit in Unicode escape.")
            }
            value = (value << 4) | digit
        }
        return value
    }

    private func skipUnsupportedValue() throws {
        guard let scalar = peek else { throw error("Missing JSON value.") }
        if scalar.value == 0x7B || scalar.value == 0x5B {
            var stack: [UInt32] = []
            var insideString = false
            var escaped = false
            while let current = peek {
                index += 1
                if insideString {
                    if escaped { escaped = false }
                    else if current.value == 0x5C { escaped = true }
                    else if current.value == 0x22 { insideString = false }
                    else if current.value < 0x20 { throw error("Unescaped control character in JSON string.") }
                    continue
                }
                if current.value == 0x22 { insideString = true }
                else if current.value == 0x7B { stack.append(0x7D) }
                else if current.value == 0x5B { stack.append(0x5D) }
                else if current.value == 0x7D || current.value == 0x5D {
                    guard current.value == stack.last else { throw error("Mismatched JSON container.") }
                    stack.removeLast()
                    if stack.isEmpty { return }
                }
            }
            throw error("Unterminated nested JSON value.")
        }
        let start = index
        while let current = peek, current.value != 0x2C, current.value != 0x7D,
              current.value != 0x20, current.value != 0x09,
              current.value != 0x0A, current.value != 0x0D { index += 1 }
        guard index > start else { throw error("Invalid JSON value.") }
        let token = String(String.UnicodeScalarView(scalars[start..<index]))
        guard token == "true" || token == "false" || token == "null" else {
            throw error("Invalid JSON value.")
        }
    }

    private var peek: Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }
    private var atEnd: Bool { index == scalars.count }

    private func take(_ scalar: Unicode.Scalar) -> Bool {
        guard peek == scalar else { return false }
        index += 1
        return true
    }

    private func skipWhitespace() {
        while let scalar = peek, scalar.value == 0x20 || scalar.value == 0x09
            || scalar.value == 0x0A || scalar.value == 0x0D { index += 1 }
    }

    private func error(_ message: String) -> StrictJSONError {
        StrictJSONError(path: "$", message: "\(message) (scalar offset \(index))", isDuplicateKey: false)
    }
}
