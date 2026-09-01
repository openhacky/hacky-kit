import Foundation

public enum HackyPDFRenderer {
    public static let pageSize = 1_800.0
    public static let dotRadius = 42.75

    /// Renders one conforming `.hacky.pdf` carrier.
    public static func render(
        _ document: HackyDocument,
        cover: HackyCoverGrid = .neutral
    ) throws -> Data {
        let json = try HackyJSONEncoder.string(document)
        let content = contentStream(json: json, cover: cover)
        let objects: [Data] = [
            plain("<< /Type /Catalog /Pages 2 0 R >>"),
            plain("<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
            plain("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1800 1800] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"),
            stream(content),
            plain("<< /Type /Font /Subtype /Type0 /BaseFont /HackyUnicode /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 7 0 R >>"),
            plain("<< /Type /Font /Subtype /CIDFontType2 /BaseFont /HackyUnicode /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 1000 /CIDToGIDMap /Identity >>"),
            stream(toUnicodeCMap(for: json)),
        ]
        return assemble(objects)
    }

    /// Writes a canonical JSON file or PDF carrier based on compound suffix.
    public static func write(
        _ document: HackyDocument,
        to url: URL,
        cover: HackyCoverGrid = .neutral
    ) throws {
        let lower = url.lastPathComponent.lowercased()
        let data: Data
        if lower.hasSuffix(".hacky.pdf") {
            data = try render(document, cover: cover)
        } else if lower.hasSuffix(".hacky.json") {
            data = try HackyJSONEncoder.encode(document)
        } else {
            throw HackyPDFRenderError.unsupportedFilename
        }
        try data.write(to: url, options: .atomic)
    }

    /// Writes a process-lifetime PDF suitable for a share sheet.
    public static func temporaryFileURL(
        _ document: HackyDocument,
        cover: HackyCoverGrid = .neutral
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hacky", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(safeFilename(document.name) + ".hacky.pdf")
        try render(document, cover: cover).write(to: url, options: .atomic)
        return url
    }

    private static func contentStream(json: String, cover: HackyCoverGrid) -> String {
        let cell = pageSize / Double(HackyCoverGrid.side)
        var content = "0.949020 0.949020 0.949020 rg 0 0 1800 1800 re f\n"
        for row in 0..<HackyCoverGrid.side {
            for column in 0..<HackyCoverGrid.side {
                let offset = (row * HackyCoverGrid.side + column) * 3
                let x = (Double(column) + 0.5) * cell
                let y = pageSize - (Double(row) + 0.5) * cell
                content += "\(format(Double(cover.rgb[offset]) / 255.0)) \(format(Double(cover.rgb[offset + 1]) / 255.0)) \(format(Double(cover.rgb[offset + 2]) / 255.0)) rg \(circlePath(x: x, y: y, radius: dotRadius)) f\n"
            }
        }
        content += "BT /F1 4 Tf 3 Tr 1 0 0 1 60 1740 Tm\n"
        content += "<\(utf16BEHex(json))> Tj\nET\n"
        return content
    }

    private static func circlePath(x: Double, y: Double, radius: Double) -> String {
        let k = radius * 0.552284749831
        return "\(format(x + radius)) \(format(y)) m "
            + "\(format(x + radius)) \(format(y + k)) \(format(x + k)) \(format(y + radius)) \(format(x)) \(format(y + radius)) c "
            + "\(format(x - k)) \(format(y + radius)) \(format(x - radius)) \(format(y + k)) \(format(x - radius)) \(format(y)) c "
            + "\(format(x - radius)) \(format(y - k)) \(format(x - k)) \(format(y - radius)) \(format(x)) \(format(y - radius)) c "
            + "\(format(x + k)) \(format(y - radius)) \(format(x + radius)) \(format(y - k)) \(format(x + radius)) \(format(y)) c"
    }

    private static func utf16BEHex(_ value: String) -> String {
        value.utf16.map { String(format: "%04X", $0) }.joined()
    }

    private static func toUnicodeCMap(for source: String) -> String {
        let units = Set(source.utf16).sorted()
        var lines = [
            "/CIDInit /ProcSet findresource begin",
            "12 dict begin",
            "begincmap",
            "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def",
            "/CMapName /HackyUnicode def",
            "/CMapType 2 def",
            "1 begincodespacerange",
            "<0000> <FFFF>",
            "endcodespacerange",
        ]
        for chunk in stride(from: 0, to: units.count, by: 100) {
            let values = Array(units[chunk..<min(chunk + 100, units.count)])
            lines.append("\(values.count) beginbfchar")
            for unit in values {
                let hex = String(format: "%04X", unit)
                lines.append("<\(hex)> <\(hex)>")
            }
            lines.append("endbfchar")
        }
        lines += ["endcmap", "CMapName currentdict /CMap defineresource pop", "end", "end"]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func plain(_ value: String) -> Data { Data(value.utf8) }

    private static func stream(_ value: String) -> Data {
        let data = Data(value.utf8)
        var output = Data("<< /Length \(data.count) >>\nstream\n".utf8)
        output.append(data)
        output.append(Data("endstream".utf8))
        return output
    }

    private static func assemble(_ objects: [Data]) -> Data {
        var output = Data("%PDF-1.4\n%Hacky\n".utf8)
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(output.count)
            output.append(Data("\(index + 1) 0 obj\n".utf8))
            output.append(object)
            output.append(Data("\nendobj\n".utf8))
        }
        let crossReference = output.count
        output.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() {
            output.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
        }
        output.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReference)\n%%EOF".utf8))
        return output
    }

    private static func safeFilename(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "hacky" : cleaned).prefix(80))
    }

    private static func format(_ value: Double) -> String {
        let raw = String(format: "%.6f", value)
        return raw.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

public enum HackyPDFRenderError: Error, LocalizedError, Sendable {
    case unsupportedFilename

    public var errorDescription: String? {
        "Output filename must end in .hacky.json or .hacky.pdf."
    }
}

public struct HackyPDFInspection: Sendable {
    public let document: HackyDocument
    public let canonicalJSON: Data
    public let pageWidth: Double
    public let pageHeight: Double
    public let vectorCircleCount: Int

    init(
        document: HackyDocument,
        canonicalJSON: Data,
        pageWidth: Double,
        pageHeight: Double,
        vectorCircleCount: Int
    ) {
        self.document = document
        self.canonicalJSON = canonicalJSON
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.vectorCircleCount = vectorCircleCount
    }
}

public enum HackyPDFExtractor {
    public static let maximumCarrierByteCount = 4 * 1_024 * 1_024

    /// Performs fail-closed preflight, extracts invisible JSON, and validates it.
    public static func inspect(_ data: Data) throws -> HackyPDFInspection {
        guard data.count <= maximumCarrierByteCount else {
            throw HackyPDFExtractionError.tooLarge
        }
        guard data.starts(with: Data("%PDF-1.4\n".utf8)) else {
            throw HackyPDFExtractionError.unsupportedVersion
        }
        guard data.allSatisfy({ $0 == 0x0A || (0x20...0x7E).contains($0) }) else {
            throw HackyPDFExtractionError.malformed
        }
        guard let raw = String(data: data, encoding: .isoLatin1) else {
            throw HackyPDFExtractionError.malformed
        }
        let eofRanges = ranges(of: "%%EOF", in: raw)
        guard eofRanges.count == 1, let eof = eofRanges.first else {
            throw HackyPDFExtractionError.multipleOrMissingEOF
        }
        let trailing = raw[eof.upperBound...]
        guard trailing.isEmpty else {
            throw HackyPDFExtractionError.trailingPayload
        }

        let forbidden = [
            "/Encrypt", "/OpenAction", "/AA", "/JavaScript", "/JS", "/Launch",
            "/URI", "/SubmitForm", "/ImportData", "/ResetForm", "/GoTo", "/GoToR",
            "/GoToE", "/Named", "/Sound", "/Movie", "/Rendition", "/Trans",
            "/RichMedia", "/AcroForm", "/XFA", "/Annots", "/EmbeddedFiles",
            "/EmbeddedFile", "/Filespec", "/FileAttachment", "/Collection", "/ObjStm",
            "/XRef", "/Filter", "/DecodeParms", "/Metadata", "/PieceInfo",
            "/XObject", "/Subtype /Image",
        ]
        if raw.contains("#") {
            throw HackyPDFExtractionError.forbiddenFeature("PDF name escape")
        }
        if let token = forbidden.first(where: {
            raw.range(of: $0, options: .caseInsensitive) != nil
        }) {
            throw HackyPDFExtractionError.forbiddenFeature(token)
        }
        let allowedNames: Set<String> = [
            "Adobe", "BaseFont", "CIDFontType2", "CIDInit", "CIDSystemInfo",
            "Adobe-Identity-UCS", "CIDToGIDMap", "CMap", "CMapName", "CMapType",
            "Catalog", "Contents",
            "Count", "DW", "DescendantFonts", "Encoding", "F1", "Font",
            "HackyUnicode", "Helvetica", "Identity", "Identity-H", "Kids", "Length", "MediaBox",
            "Ordering", "Page", "Pages", "Parent", "ProcSet", "Registry", "Resources",
            "Root", "Size", "Subtype", "Supplement", "ToUnicode", "Type", "Type0",
            "UCS",
        ]
        let names = try pdfNames(in: raw)
        if let name = names.first(where: { !allowedNames.contains($0) }) {
            throw HackyPDFExtractionError.forbiddenFeature("/\(name)")
        }
        guard raw.hasPrefix("%PDF-1.4\n%"),
              ranges(of: "%", in: raw).count == 4,
              ranges(of: " obj\n", in: raw).count == 7,
              ranges(of: "\nendobj", in: raw).count == 7,
              ranges(of: "/Type /Catalog", in: raw).count == 1,
              ranges(of: "/Type /Pages", in: raw).count == 1,
              ranges(of: "/Type /Page ", in: raw).count == 1,
              regexCount(#"/Count\s+1\b"#, in: raw) == 1,
              regexCount(
                #"/MediaBox\s*\[0(?:\.0+)?\s+0(?:\.0+)?\s+1800(?:\.0+)?\s+1800(?:\.0+)?\]"#,
                in: raw
              ) == 1,
              ranges(of: "\nxref\n", in: raw).count == 1,
              ranges(of: "trailer\n", in: raw).count == 1,
              ranges(of: "startxref\n", in: raw).count == 1,
              raw.contains("/ToUnicode"),
              raw.contains("/CIDToGIDMap /Identity") else {
            throw HackyPDFExtractionError.nonconformingStructure
        }

        let streams = try extractStreams(from: raw)
        guard streams.count == 2 else { throw HackyPDFExtractionError.nonconformingStructure }
        let page = streams[0]
        guard ranges(of: "BT ", in: page).count == 1,
              ranges(of: "ET\n", in: page).count == 1,
              ranges(of: "3 Tr", in: page).count == 1 else {
            throw HackyPDFExtractionError.nonconformingStructure
        }
        let embeddedHex = try preflightPageStream(page)
        let circles = HackyCoverGrid.side * HackyCoverGrid.side
        let jsonString = try decodeUTF16BEHex(embeddedHex)
        guard let json = jsonString.data(using: .utf8) else {
            throw HackyPDFExtractionError.invalidUnicode
        }
        let document: HackyDocument
        do {
            document = try HackyValidator.decode(json, requireCanonical: true)
        } catch let failure as HackyValidationFailure {
            throw HackyPDFExtractionError.invalidJSON(failure)
        }
        try preflightUnicodeMap(streams[1], requiredBy: jsonString)
        return HackyPDFInspection(
            document: document,
            canonicalJSON: json,
            pageWidth: 1_800,
            pageHeight: 1_800,
            vectorCircleCount: circles
        )
    }

    public static func extract(_ data: Data) throws -> HackyDocument {
        try inspect(data).document
    }

    /// Alias that emphasizes that inspection is a fail-closed safety preflight.
    public static func preflight(_ data: Data) throws -> HackyPDFInspection {
        try inspect(data)
    }

    private static func extractStreams(from raw: String) throws -> [String] {
        let pattern = try NSRegularExpression(
            pattern: #"<< /Length ([0-9]+) >>\nstream\n([\s\S]*?)endstream"#
        )
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        let matches = pattern.matches(in: raw, range: range)
        guard matches.count == 2 else { throw HackyPDFExtractionError.malformed }
        var output: [String] = []
        for match in matches {
            guard let lengthRange = Range(match.range(at: 1), in: raw),
                  let streamRange = Range(match.range(at: 2), in: raw),
                  let declaredLength = Int(raw[lengthRange]) else {
                throw HackyPDFExtractionError.malformed
            }
            let stream = String(raw[streamRange])
            guard stream.utf8.count == declaredLength else {
                throw HackyPDFExtractionError.malformed
            }
            output.append(stream)
        }
        return output
    }

    private static func pdfNames(in raw: String) throws -> [String] {
        let pattern = try NSRegularExpression(pattern: #"/([A-Za-z0-9-]+)"#)
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return try pattern.matches(in: raw, range: range).map { match in
            guard let range = Range(match.range(at: 1), in: raw) else {
                throw HackyPDFExtractionError.malformed
            }
            return String(raw[range])
        }
    }

    private static func preflightPageStream(_ stream: String) throws -> String {
        var cursor = ContentCursor(stream)
        let background = try cursor.numbers(count: 3)
        guard background.allSatisfy({ approximately($0, 242.0 / 255.0) }) else {
            throw HackyPDFExtractionError.nonconformingCover
        }
        try cursor.expect("rg")
        guard matches(try cursor.numbers(count: 4), [0, 0, 1_800, 1_800]) else {
            throw HackyPDFExtractionError.nonconformingCover
        }
        try cursor.expect("re")
        try cursor.expect("f")

        let cell = HackyPDFRenderer.pageSize / Double(HackyCoverGrid.side)
        let radius = HackyPDFRenderer.dotRadius
        let control = radius * 0.552284749831
        for row in 0..<HackyCoverGrid.side {
            for column in 0..<HackyCoverGrid.side {
                let color = try cursor.numbers(count: 3)
                guard color.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                    throw HackyPDFExtractionError.nonconformingCover
                }
                try cursor.expect("rg")
                let x = (Double(column) + 0.5) * cell
                let y = HackyPDFRenderer.pageSize - (Double(row) + 0.5) * cell
                guard matches(try cursor.numbers(count: 2), [x + radius, y]) else {
                    throw HackyPDFExtractionError.nonconformingCover
                }
                try cursor.expect("m")
                let curves = [
                    [x + radius, y + control, x + control, y + radius, x, y + radius],
                    [x - control, y + radius, x - radius, y + control, x - radius, y],
                    [x - radius, y - control, x - control, y - radius, x, y - radius],
                    [x + control, y - radius, x + radius, y - control, x + radius, y],
                ]
                for expected in curves {
                    guard matches(try cursor.numbers(count: 6), expected) else {
                        throw HackyPDFExtractionError.nonconformingCover
                    }
                    try cursor.expect("c")
                }
                try cursor.expect("f")
            }
        }

        try cursor.expect("BT")
        try cursor.expect("/F1")
        let fontSize = try cursor.number()
        guard fontSize.isFinite && fontSize > 0 else {
            throw HackyPDFExtractionError.nonconformingStructure
        }
        try cursor.expect("Tf")
        guard approximately(try cursor.number(), 3) else {
            throw HackyPDFExtractionError.nonconformingStructure
        }
        try cursor.expect("Tr")
        let matrix = try cursor.numbers(count: 6)
        guard matches(Array(matrix.prefix(4)), [1, 0, 0, 1]),
              matrix[4].isFinite, matrix[5].isFinite else {
            throw HackyPDFExtractionError.nonconformingStructure
        }
        try cursor.expect("Tm")
        let token = try cursor.next()
        guard token.first == "<", token.last == ">", token.count > 2 else {
            throw HackyPDFExtractionError.missingJSON
        }
        let hex = String(token.dropFirst().dropLast())
        guard hex.allSatisfy({ $0.isHexDigit }) else {
            throw HackyPDFExtractionError.invalidUnicode
        }
        try cursor.expect("Tj")
        try cursor.expect("ET")
        guard cursor.isAtEnd else {
            throw HackyPDFExtractionError.nonconformingStructure
        }
        return hex
    }

    private static func preflightUnicodeMap(_ stream: String, requiredBy value: String) throws {
        guard stream.contains("begincmap"), stream.contains("endcmap"),
              stream.contains("<0000> <FFFF>"), !stream.contains("usecmap") else {
            throw HackyPDFExtractionError.invalidUnicode
        }
        let pattern = try NSRegularExpression(
            pattern: #"<([0-9A-Fa-f]{4})>\s+<([0-9A-Fa-f]{4})>"#
        )
        let range = NSRange(stream.startIndex..<stream.endIndex, in: stream)
        var identity: Set<UInt16> = []
        for match in pattern.matches(in: stream, range: range) {
            guard let sourceRange = Range(match.range(at: 1), in: stream),
                  let targetRange = Range(match.range(at: 2), in: stream),
                  let source = UInt16(stream[sourceRange], radix: 16),
                  let target = UInt16(stream[targetRange], radix: 16) else {
                throw HackyPDFExtractionError.invalidUnicode
            }
            if source == 0, target == UInt16.max { continue }
            guard source == target else { throw HackyPDFExtractionError.invalidUnicode }
            identity.insert(source)
        }
        guard Set(value.utf16).isSubset(of: identity) else {
            throw HackyPDFExtractionError.invalidUnicode
        }
    }

    private static func approximately(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs.isFinite && rhs.isFinite && abs(lhs - rhs) <= 0.001
    }

    private static func matches(_ values: [Double], _ expected: [Double]) -> Bool {
        values.count == expected.count
            && zip(values, expected).allSatisfy { approximately($0, $1) }
    }

    private struct ContentCursor {
        private let tokens: [Substring]
        private var index = 0

        init(_ source: String) {
            tokens = source.split(whereSeparator: { $0.isWhitespace })
        }

        var isAtEnd: Bool { index == tokens.count }

        mutating func next() throws -> Substring {
            guard index < tokens.count else {
                throw HackyPDFExtractionError.nonconformingStructure
            }
            defer { index += 1 }
            return tokens[index]
        }

        mutating func expect(_ expected: Substring) throws {
            guard try next() == expected else {
                throw HackyPDFExtractionError.nonconformingStructure
            }
        }

        mutating func number() throws -> Double {
            guard let value = Double(try next()), value.isFinite else {
                throw HackyPDFExtractionError.nonconformingStructure
            }
            return value
        }

        mutating func numbers(count: Int) throws -> [Double] {
            try (0..<count).map { _ in try number() }
        }
    }

    private static func decodeUTF16BEHex(_ hex: String) throws -> String {
        guard hex.count.isMultiple(of: 4) else { throw HackyPDFExtractionError.invalidUnicode }
        var units: [UInt16] = []
        units.reserveCapacity(hex.count / 4)
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 4)
            guard let unit = UInt16(hex[index..<end], radix: 16) else {
                throw HackyPDFExtractionError.invalidUnicode
            }
            units.append(unit)
            index = end
        }
        let decoded = String(decoding: units, as: UTF16.self)
        guard Array(decoded.utf16) == units else { throw HackyPDFExtractionError.invalidUnicode }
        return decoded
    }

    private static func ranges(of needle: String, in source: String) -> [Range<String.Index>] {
        var output: [Range<String.Index>] = []
        var cursor = source.startIndex
        while cursor < source.endIndex,
              let range = source.range(of: needle, range: cursor..<source.endIndex) {
            output.append(range)
            cursor = range.upperBound
        }
        return output
    }

    private static func regexCount(_ pattern: String, in source: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.numberOfMatches(in: source, range: range)
    }
}

public enum HackyPDFExtractionError: Error, LocalizedError, Sendable {
    case tooLarge
    case unsupportedVersion
    case malformed
    case multipleOrMissingEOF
    case trailingPayload
    case forbiddenFeature(String)
    case nonconformingStructure
    case nonconformingCover
    case missingJSON
    case invalidUnicode
    case invalidJSON(HackyValidationFailure)

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "Carrier exceeds the preflight size limit."
        case .unsupportedVersion: "Carrier must begin with PDF 1.4."
        case .malformed: "Carrier is malformed."
        case .multipleOrMissingEOF: "Carrier must contain exactly one EOF marker."
        case .trailingPayload: "Carrier contains bytes after EOF."
        case .forbiddenFeature(let token): "Carrier contains forbidden PDF feature \(token)."
        case .nonconformingStructure: "Carrier does not match the one-page Hacky safe subset."
        case .nonconformingCover: "Carrier does not contain exactly 256 vector circles."
        case .missingJSON: "Carrier has no extractable invisible Hacky JSON."
        case .invalidUnicode: "Carrier text is not lossless Unicode."
        case .invalidJSON(let failure): failure.localizedDescription
        }
    }
}
