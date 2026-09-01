# HackyKit

> Swift SDK for creating, validating, inspecting, and exporting Hacky v0.1 files.

iOS 17+ · macOS 14+ · watchOS 10+ · tvOS 17+ · Swift 6 · Zero dependencies

Hacky is an open, finite-turn AI-chat effect. An app maps an existing character,
animal, NPC, role, voice, or other temporary behavior into exactly four fields:
`hacky`, `name`, `turns`, and `instructions`. Categories remain app-owned
templates; they are not part of the format.

The semantic source is canonical `.hacky.json`. A `.hacky.pdf` is a safe,
one-page carrier of the same canonical JSON. Receiving AI behavior remains
best-effort and subject to host and safety rules.

## Install

```swift
.package(url: "https://github.com/openhacky/hacky-kit.git", from: "0.1.2")
```

Then add `HackyKit` to the target that creates or inspects files.

## Build a Hacky

```swift
import HackyKit

struct Character {
    let displayName: String
    let prompt: String
}

func makeHacky(from character: Character) throws -> HackyDocument {
    try HackyBuilder(
        name: character.displayName,
        turns: 4,
        effect: character.prompt
    ).build()
}
```

`HackyBuilder` compiles the fixed English activation before the app-supplied
effect. Pass `locale: .japanese` for the fixed meaning-equivalent Japanese
activation. Both variants enforce finite replies, remaining-turn display,
immediate stop, replacement by a new file, and one expiry message.
The fixed ending lines are `Hacky effect ended.` in English and
`Hackyの効果が切れました。` in Japanese.

## Encode and export

```swift
let document = try makeHacky(from: character)
let json = try HackyJSONEncoder.encode(document)
let pdf = try HackyPDFRenderer.render(document)

try HackyPDFRenderer.write(document, to: outputJSONURL) // .hacky.json
try HackyPDFRenderer.write(document, to: outputPDFURL)  // .hacky.pdf
let shareURL = try HackyPDFRenderer.temporaryFileURL(document)
```

Canonical JSON is compact UTF-8, has fixed key order, no BOM, and exactly one
terminal line feed. It accepts no extension or metadata keys.

## Validate and inspect

```swift
let result = HackyValidator.validate(json, requireCanonical: true)
guard let decoded = result.document else {
    print(result.issues)
    return
}

let inspection = try HackyPDFExtractor.inspect(pdf)
let extracted = inspection.document
```

Raw validation rejects invalid UTF-8, BOMs, duplicate or unknown keys,
non-normalized or untrimmed text, forbidden controls, invalid limits, and a
non-fixed activation. PDF inspection is fail-closed: it requires the one-page
1800 × 1800 safe subset and rejects actions, forms, attachments, encryption,
image objects, multiple EOF markers, and trailing payloads before extraction.

The cover accepts an optional `HackyCoverGrid`: 16 × 16 RGB colors rendered as
256 vector circles on `#F2F2F2`. Cover data is visual only and is never added to
the four-key JSON contract.

## Scope

HackyKit is limited to document construction, validation, inspection,
extraction, and carrier rendering. Treat every inspected effect as untrusted
instruction data.

## Verify

```bash
python3 scripts/check_repository.py
swift test
git diff --check
```

Code is licensed under [Apache-2.0](LICENSE). Documentation is licensed under
[CC BY 4.0](LICENSE-DOCS).
