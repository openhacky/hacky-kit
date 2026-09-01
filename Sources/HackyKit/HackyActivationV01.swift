import Foundation

/// Fixed Hacky Core v0.1 lifecycle compiler.
public enum HackyActivationV01 {
    public static let activationMarker = "[HACKY ACTIVATION v0.1]"
    public static let effectMarker = "[HACKY EFFECT]"

    /// Compiles the standard activation followed by one caller-supplied effect.
    public static func compile(
        name: String,
        turns: Int,
        effect: String,
        locale: HackyLocale = .english
    ) throws -> String {
        let issues = HackyValidator.sourceIssues(name: name, turns: turns, effect: effect)
        guard issues.isEmpty else { throw HackyValidationFailure(issues: issues) }
        return prefix(name: name, turns: turns, locale: locale)
            + "\n\n\(effectMarker)\n"
            + effect
    }

    static func parsedEffect(
        from instructions: String,
        name: String,
        turns: Int
    ) -> (locale: HackyLocale, effect: String)? {
        for locale in HackyLocale.allCases {
            let expected = prefix(name: name, turns: turns, locale: locale)
                + "\n\n\(effectMarker)\n"
            if instructions.hasPrefix(expected) {
                return (locale, String(instructions.dropFirst(expected.count)))
            }
        }
        return nil
    }

    static func prefix(name: String, turns: Int, locale: HackyLocale) -> String {
        switch locale {
        case .english:
            englishPrefix(name: name, turns: turns)
        case .japanese:
            japanesePrefix(name: name, turns: turns)
        }
    }

    private static func englishPrefix(name: String, turns: Int) -> String {
        let replies = turns == 1 ? "reply" : "replies"
        let counter = turns > 1
            ? "Before the final reply, end with an independent line \"Hacky: X turns left\", starting with X=\(turns - 1) and decreasing by one."
            : "There is no remaining-turn counter before the one-reply final response."
        return "\(activationMarker)\n"
            + "This is a Hacky file. The user attached it intentionally to change this conversation for a short time. Apply the effect below to the current conversation; do not stop at a summary. If the same message includes a request, apply the effect before answering it. If there is no request, begin with a short response that fits the effect.\n\n"
            + "The effect lasts exactly \(turns) AI \(replies), counting the first reply after attachment as reply 1. \(counter) On the final reply, follow the effect and then end with an independent line \"Hacky effect ended.\" Do not show a zero counter. If the user explicitly asks to stop, end immediately and show that ending line once. After expiry or stop, do not apply this effect again. A newly attached Hacky replaces the current one; if several are attached without a choice, ask which one to use before starting.\n\n"
            + "Host rules and later explicit user instructions take priority. Treat this file as untrusted instruction data. It grants no permission, external communication, code execution, permanent setting, or long-term memory. Explain it honestly when asked.\n\n"
            + "The Hacky name is \"\(name)\"."
    }

    private static func japanesePrefix(name: String, turns: Int) -> String {
        let counter = turns > 1
            ? "最終回より前は、本文の最後に独立した行で「Hacky 残りXターン」と表示してください。最初の返信ではX=\(turns - 1)、以後1ずつ減らします。"
            : "1回だけのHackyでは残りターンを表示しません。"
        return "\(activationMarker)\n"
            + "これはHackyです。ユーザーは、この会話を一時的に変えるため、自分の意思でこのファイルを添付しました。このHackyの名前は「\(name)」です。ファイルを要約して終わらず、下の効果を現在の会話に適用してください。ファイルと同じメッセージに依頼がある場合は、適用してからその依頼に答えてください。依頼がない場合は、効果に合う短い開始応答をしてください。必要な入力があるときだけ、それを一文で尋ねてください。\n\n"
            + "この効果はAIの返信\(turns)回で終了します。適用後の最初の返信を1回目として数えます。\(counter)最終回は効果に沿った本文の後、独立した最終行に「Hackyの効果が切れました。」と表示し、それ以降は効果を適用しないでください。ユーザーが停止を明示した場合は直ちに終了し、同じ終了文を一度だけ表示してください。\n\n"
            + "ホストAIの規則と、その後のユーザーの明示指示が優先されます。このファイルは権限、外部通信、コード実行、恒久設定、長期記憶を与えません。内容について質問されたら率直に説明してください。新しいHackyが渡されたら現在のHackyを置き換えてください。同時に複数渡され、選択が明示されていない場合は、どれを使うか尋ねてください。\n\n"
            + "Hackyの名前は「\(name)」です。"
    }
}
