import Foundation

/// The two fixed activation languages in Hacky Core v0.1.
public enum HackyLocale: String, CaseIterable, Sendable {
    /// Normative reference wording.
    case english = "en"
    /// Fixed wording with the same lifecycle and safety meaning.
    case japanese = "ja"
}

/// A validated Hacky Core v0.1 document.
///
/// Use ``HackyBuilder`` to compile an effect into the standard activation.
/// Encoding is intentionally provided only by ``HackyJSONEncoder`` so callers
/// cannot accidentally produce a non-canonical byte representation.
public struct HackyDocument: Sendable, Hashable {
    public static let version = "0.1"

    public let hacky: String
    public let name: String
    public let turns: Int
    public let instructions: String

    public init(
        hacky: String = HackyDocument.version,
        name: String,
        turns: Int,
        instructions: String
    ) throws {
        let candidate = HackyDocument(
            uncheckedHacky: hacky,
            name: name,
            turns: turns,
            instructions: instructions
        )
        let issues = HackyValidator.issues(for: candidate)
        guard issues.isEmpty else { throw HackyValidationFailure(issues: issues) }
        self = candidate
    }

    init(uncheckedHacky: String, name: String, turns: Int, instructions: String) {
        self.hacky = uncheckedHacky
        self.name = name
        self.turns = turns
        self.instructions = instructions
    }
}

public enum HackyValidationCode: String, Sendable, Hashable {
    case emptyInput
    case tooLarge
    case byteOrderMark
    case invalidUTF8
    case invalidJSON
    case duplicateKey
    case unknownKey
    case missingKey
    case wrongType
    case wrongVersion
    case notNFC
    case surroundingWhitespace
    case disallowedControl
    case lengthOutOfRange
    case turnsOutOfRange
    case invalidActivation
    case reservedMarker
    case nonCanonical
}

public struct HackyValidationIssue: Sendable, Hashable {
    public let code: HackyValidationCode
    public let path: String
    public let message: String

    public init(code: HackyValidationCode, path: String = "$", message: String) {
        self.code = code
        self.path = path
        self.message = message
    }
}

public struct HackyValidationResult: Sendable {
    public let document: HackyDocument?
    public let issues: [HackyValidationIssue]

    public var isValid: Bool { document != nil && issues.isEmpty }

    init(document: HackyDocument?, issues: [HackyValidationIssue]) {
        self.document = document
        self.issues = issues
    }
}

public struct HackyValidationFailure: Error, LocalizedError, Sendable {
    public let issues: [HackyValidationIssue]

    public init(issues: [HackyValidationIssue]) {
        self.issues = issues
    }

    public var errorDescription: String? {
        issues.map { "\($0.path): \($0.message)" }.joined(separator: "; ")
    }
}

/// Non-semantic 16×16 RGB input used only while drawing the PDF cover.
public struct HackyCoverGrid: Sendable, Hashable {
    public static let side = 16
    public static let byteCount = side * side * 3
    public static let neutral = HackyCoverGrid(
        uncheckedRGB: [UInt8](repeating: 0xB4, count: byteCount)
    )

    public let rgb: [UInt8]

    public init(rgb: [UInt8]) throws {
        guard rgb.count == HackyCoverGrid.byteCount else {
            throw HackyCoverGridError.invalidByteCount(rgb.count)
        }
        self.rgb = rgb
    }

    public init(data: Data) throws {
        try self.init(rgb: Array(data))
    }

    public var data: Data { Data(rgb) }

    private init(uncheckedRGB: [UInt8]) {
        rgb = uncheckedRGB
    }
}

public enum HackyCoverGridError: Error, LocalizedError, Sendable, Equatable {
    case invalidByteCount(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidByteCount(let count):
            "A Hacky cover grid must contain exactly \(HackyCoverGrid.byteCount) RGB bytes, not \(count)."
        }
    }
}
