import Foundation

/// Maps one app-owned effect into a conforming Hacky Core v0.1 document.
public struct HackyBuilder: Sendable {
    public let name: String
    public let turns: Int
    public let effect: String
    public let locale: HackyLocale

    public init(
        name: String,
        turns: Int = 4,
        effect: String,
        locale: HackyLocale = .english
    ) {
        self.name = name
        self.turns = turns
        self.effect = effect
        self.locale = locale
    }

    public func build() throws -> HackyDocument {
        let instructions = try HackyActivationV01.compile(
            name: name,
            turns: turns,
            effect: effect,
            locale: locale
        )
        return try HackyDocument(name: name, turns: turns, instructions: instructions)
    }
}
