import Foundation

public enum InputMethod: String, Codable, CaseIterable {
    case telex, vni, simpleTelex, viqr

    public var displayName: String {
        switch self {
        case .telex: return "Telex"
        case .vni: return "VNI"
        case .simpleTelex: return "Simple Telex"
        case .viqr: return "VIQR"
        }
    }

    /// Telex và Simple Telex dùng chung chữ cái làm dấu.
    var isTelex: Bool { self == .telex || self == .simpleTelex }
}

/// Kết quả xử lý một phím: xoá `backspaces` ký tự trước con trỏ rồi chèn `text`.
public struct EditResult: Equatable {
    public let backspaces: Int
    public let text: String

    public init(backspaces: Int, text: String) {
        self.backspaces = backspaces
        self.text = text
    }
}

enum Tone: Int {
    case none = 0, sac, huyen, hoi, nga, nang
}

enum Mark {
    case none, circumflex, breve, horn, stroke
}

struct VChar {
    var base: Character          // chữ thường ASCII: a-z hoặc chữ số
    var mark: Mark = .none
    var upper: Bool
    var fromStandaloneW = false  // "ư" sinh ra từ phím w đứng riêng (Telex)

    var isVowel: Bool {
        switch base {
        case "a", "e", "i", "o", "u", "y": return true
        default: return false
        }
    }
}

/// Bộ xử lý một âm tiết tiếng Việt. Không phụ thuộc AppKit nên kiểm thử được độc lập.
///
/// Nguyên tắc chống lỗi: engine luôn giữ `screen` = đúng những gì đã gõ ra màn hình
/// cho từ hiện tại, và mỗi phím chỉ phát ra phần chênh lệch (xoá phần khác + chèn phần mới).
public final class VietnameseEngine {
    public var method: InputMethod
    /// true: hoà, thuỷ, khoẻ — false: hòa, thủy, khỏe
    public var modernToneStyle: Bool
    /// Tự trả lại phím gốc khi từ không thể là tiếng Việt (vd: "windows", "google").
    public var autoRestoreEnglish: Bool
    /// Telex: gõ đôi phụ âm đầu từ ra phụ âm ghép (cc → ch, gg → gi, kk → kh, nn → ng, qq → qu, pp → ph, tt → th).
    public var quickTelex = false
    /// Phụ âm đầu gõ tắt: f → ph, j → gi, w → qu.
    public var quickStartConsonant = false
    /// Phụ âm cuối gõ tắt ngay sau nguyên âm: g → ng, h → nh, k → ch.
    public var quickEndConsonant = false
    /// Từ kế tiếp được gõ nguyên phím, không thêm dấu (nhấn-thả ⌥ trước khi gõ). Tự tắt sau một từ.
    public var typeNextWordAsIs = false

    private var chars: [VChar] = []
    private var tone: Tone = .none
    private var raw: [Character] = []
    private var locked = false
    private var screen: [Character] = []

    public init(method: InputMethod = .telex, modernToneStyle: Bool = true, autoRestoreEnglish: Bool = true) {
        self.method = method
        self.modernToneStyle = modernToneStyle
        self.autoRestoreEnglish = autoRestoreEnglish
    }

    public var isEmpty: Bool { screen.isEmpty }
    public var currentWord: String { String(screen) }
    /// Các phím đã gõ cho từ hiện tại ("ddc" khi màn hình là "ddc", "vieetj" khi màn hình là "việt").
    public var typedKeys: String { String(raw) }

    public func reset() {
        chars = []
        tone = .none
        raw = []
        locked = false
        screen = []
    }

    /// Xử lý một ký tự. Trả về nil nếu phím không thuộc về từ đang gõ (caller nên reset và cho phím đi qua).
    public func process(_ key: Character) -> EditResult? {
        guard key.isASCII else { return nil }
        if method == .viqr && !key.isLetter && !key.isNumber { return processVIQRSymbol(key) }
        let isLetter = key.isLetter
        let isDigit = key.isNumber
        if !(isLetter || (isDigit && method == .vni && !chars.isEmpty)) {
            return nil
        }

        let lower = Character(key.lowercased())
        let upper = key.isUppercase
        if raw.isEmpty && typeNextWordAsIs {
            typeNextWordAsIs = false
            locked = true
        }
        raw.append(key)

        if locked {
            chars.append(VChar(base: lower, upper: upper))
        } else {
            if !applyQuickConsonant(lower, upper: upper) {
                let handled: Bool
                switch method {
                case .telex, .simpleTelex: handled = applyTelex(lower, upper: upper)
                case .vni: handled = applyVNI(lower, upper: upper)
                case .viqr: handled = lower == "d" && applyStroke(key: lower, upper: upper)
                }
                if !handled && !applyQuickEnd(lower, upper: upper) {
                    chars.append(VChar(base: lower, upper: upper))
                }
            }
            if !locked && autoRestoreEnglish && !isValidSyllable() && render() != raw {
                chars = raw.map { VChar(base: Character($0.lowercased()), upper: $0.isUppercase) }
                tone = .none
                locked = true
            }
        }
        return commit()
    }

    /// Người dùng kết thúc từ (Space, dấu câu, Enter…). Lúc đang gõ engine phải cho qua những dạng
    /// chưa xong như "ue" (sắp thành "uê") hay "tẽt" (sắp đổi sang "tét"); tới đây từ đã xong nên
    /// kiểm chặt: không phải âm tiết tiếng Việt thì trả lại phím gốc ("user" → "ủe" → "user").
    /// Trả nil nếu không cần đổi gì. Engine luôn được reset.
    public func finishWord() -> EditResult? {
        defer { reset() }
        guard !screen.isEmpty else { return nil }
        // Từ tiếng Anh mà Telex gõ hỏng: "different" → "diferent", "more" → "moẻ" (xem EnglishWords.swift)
        if autoRestoreEnglish && method.isTelex && screen != raw && EnglishWords.contains(String(raw).lowercased()) {
            chars = raw.map { VChar(base: Character($0.lowercased()), upper: $0.isUppercase) }
            tone = .none
            return commit()
        }
        guard !locked else { return nil }
        // "ươ" không có âm cuối viết là "uơ": thuowr → thuở (gõ tiếp "ng" thì vẫn là "thương")
        let p = split()
        if p.final.isEmpty, p.nucleus.count == 2,
           chars[p.nucleus.lowerBound].base == "u", chars[p.nucleus.lowerBound].mark == .horn,
           chars[p.nucleus.lowerBound + 1].base == "o", chars[p.nucleus.lowerBound + 1].mark == .horn {
            chars[p.nucleus.lowerBound].mark = .none
        }
        if autoRestoreEnglish && render() != raw && !isCompleteSyllable() {
            chars = raw.map { VChar(base: Character($0.lowercased()), upper: $0.isUppercase) }
            tone = .none
        }
        let result = commit()
        return result.backspaces == 0 && result.text.isEmpty ? nil : result
    }

    /// Esc: trả lại đúng các phím đã gõ cho từ hiện tại, phần còn lại của từ gõ nguyên phím.
    /// Trả nil nếu từ đã đúng bằng phím gốc (khi đó Esc nên đi qua bình thường).
    public func restoreRaw() -> EditResult? {
        guard !screen.isEmpty, screen != raw else { return nil }
        chars = raw.map { VChar(base: Character($0.lowercased()), upper: $0.isUppercase) }
        tone = .none
        locked = true
        return commit()
    }

    /// Người dùng nhấn Backspace. Trả về false nếu engine không có gì để xoá.
    /// Phím Backspace thật vẫn được gửi đi; engine chỉ đồng bộ trạng thái.
    @discardableResult
    public func backspace() -> Bool {
        guard !screen.isEmpty else { return false }
        screen.removeLast()
        if screen.isEmpty {
            reset()
            return true
        }
        if locked {
            chars.removeLast()
            raw = chars.map { $0.upper ? Character($0.base.uppercased()) : $0.base }
            return true
        }
        let tonePos = tonePosition()
        chars.removeLast()
        if tonePos == chars.count { tone = .none }
        rebuildRaw()
        return true
    }

    // MARK: - Telex

    private func applyTelex(_ k: Character, upper: Bool) -> Bool {
        switch k {
        case "s": return applyTone(.sac, key: k, upper: upper)
        case "f": return applyTone(.huyen, key: k, upper: upper)
        case "r": return applyTone(.hoi, key: k, upper: upper)
        case "x": return applyTone(.nga, key: k, upper: upper)
        case "j": return applyTone(.nang, key: k, upper: upper)
        case "z":
            if tone != .none && nucleus() != nil { tone = .none; return true }
            return false
        case "a", "e", "o": return applyCircumflex(target: k, key: k, upper: upper)
        case "w": return applyHorn(key: k, upper: upper, allowBreve: true, standalone: method == .telex)
        case "d": return applyStroke(key: k, upper: upper)
        default: return false
        }
    }

    // MARK: - VNI

    private func applyVNI(_ k: Character, upper: Bool) -> Bool {
        switch k {
        case "1": return applyTone(.sac, key: k, upper: upper)
        case "2": return applyTone(.huyen, key: k, upper: upper)
        case "3": return applyTone(.hoi, key: k, upper: upper)
        case "4": return applyTone(.nga, key: k, upper: upper)
        case "5": return applyTone(.nang, key: k, upper: upper)
        case "0":
            if tone != .none && nucleus() != nil { tone = .none; return true }
            return false
        case "6": return applyCircumflex(target: nil, key: k, upper: upper)
        case "7": return applyHorn(key: k, upper: upper, allowBreve: false, standalone: false)
        case "8": return applyBreve(key: k, upper: upper)
        case "9": return applyStroke(key: k, upper: upper)
        default: return false
        }
    }

    // MARK: - Biến đổi

    private func undo(appending key: Character, upper: Bool) -> Bool {
        chars.append(VChar(base: key, upper: upper))
        locked = true
        return true
    }

    private func applyTone(_ t: Tone, key: Character, upper: Bool) -> Bool {
        guard nucleus() != nil, isValidSyllable() else { return false }
        if tone == t {
            tone = .none
            return undo(appending: key, upper: upper)
        }
        tone = t
        return true
    }

    /// target: nguyên âm cần thêm mũ (Telex: aa/ee/oo). nil = nguyên âm a/e/o gần cuối nhất (VNI: 6).
    private func applyCircumflex(target: Character?, key: Character, upper: Bool) -> Bool {
        guard let nuc = nucleus() else { return false }
        let candidates: Set<Character> = target.map { [$0] } ?? ["a", "e", "o"]
        guard let idx = nuc.last(where: { candidates.contains(chars[$0].base) }) else { return false }
        if chars[idx].mark == .circumflex {
            chars[idx].mark = .none
            return undo(appending: key, upper: upper)
        }
        chars[idx].mark = .circumflex
        return true
    }

    private func applyBreve(key: Character, upper: Bool) -> Bool {
        guard let nuc = nucleus(), let idx = nuc.last(where: { chars[$0].base == "a" }) else { return false }
        if chars[idx].mark == .breve {
            chars[idx].mark = .none
            return undo(appending: key, upper: upper)
        }
        chars[idx].mark = .breve
        return true
    }

    // MARK: - VIQR

    /// a' á · a` à · a? ả · a~ ã · a. ạ · a^ â · a( ă · o+ ơ · dd đ. Gõ \ ngay sau từ để gõ tiếp nguyên phím (đi\. → "đi.").
    private static let viqrSymbols: Set<Character> = ["'", "`", "?", "~", ".", "^", "(", "+", "\\"]

    /// Ký hiệu VIQR chỉ thuộc về từ khi nó thật sự đổi được từ; nếu không ("đi?" khi đã có dấu…)
    /// thì trả nil, phím đi qua như dấu câu bình thường.
    private func processVIQRSymbol(_ key: Character) -> EditResult? {
        guard Self.viqrSymbols.contains(key), !chars.isEmpty, !locked else { return nil }
        if key == "\\" {
            locked = true
            return EditResult(backspaces: 0, text: "")  // nuốt dấu "\\"
        }
        let saved = (chars, tone, raw)
        raw.append(key)
        let handled: Bool
        switch key {
        case "'": handled = applyTone(.sac, key: key, upper: false)
        case "`": handled = applyTone(.huyen, key: key, upper: false)
        case "?": handled = applyTone(.hoi, key: key, upper: false)
        case "~": handled = applyTone(.nga, key: key, upper: false)
        case ".": handled = applyTone(.nang, key: key, upper: false)
        case "^": handled = applyCircumflex(target: nil, key: key, upper: false)
        case "(": handled = applyBreve(key: key, upper: false)
        default: handled = applyHorn(key: key, upper: false, allowBreve: false, standalone: false)
        }
        if handled { return commit() }
        (chars, tone, raw) = saved
        return nil
    }

    // MARK: - Phụ âm gõ tắt

    private static let quickTelexPairs: [Character: Character] = [
        "c": "h", "g": "i", "k": "h", "n": "g", "q": "u", "p": "h", "t": "h",
    ]
    private static let quickStartPairs: [Character: (Character, Character)] = [
        "f": ("p", "h"), "j": ("g", "i"), "w": ("q", "u"),
    ]
    private static let quickEndPairs: [Character: (Character, Character)] = [
        "g": ("n", "g"), "h": ("n", "h"), "k": ("c", "h"),
    ]

    /// Đầu từ: "cc" → "ch" (Quick Telex), "f" → "ph" (phụ âm đầu gõ tắt).
    private func applyQuickConsonant(_ k: Character, upper: Bool) -> Bool {
        if quickStartConsonant && chars.isEmpty, let (a, b) = Self.quickStartPairs[k] {
            chars.append(VChar(base: a, upper: upper))
            chars.append(VChar(base: b, upper: false))
            return true
        }
        if quickTelex && method.isTelex && chars.count == 1 && chars[0].base == k && chars[0].mark == .none,
           let second = Self.quickTelexPairs[k] {
            chars.append(VChar(base: second, upper: upper))
            return true
        }
        return false
    }

    /// Ngay sau nguyên âm: "ag" → "ang", "ah" → "anh", "ak" → "ach".
    private func applyQuickEnd(_ k: Character, upper: Bool) -> Bool {
        guard quickEndConsonant, let (a, b) = Self.quickEndPairs[k], nucleus() != nil, split().final.isEmpty
        else { return false }
        chars.append(VChar(base: a, upper: upper))
        chars.append(VChar(base: b, upper: upper))
        return true
    }

    private func applyHorn(key: Character, upper: Bool, allowBreve: Bool, standalone: Bool) -> Bool {
        guard let nuc = nucleus() else {
            // "w" đứng riêng sau phụ âm hoặc đầu từ → "ư"
            if standalone && (chars.last.map { !$0.isVowel } ?? true) {
                chars.append(VChar(base: "u", mark: .horn, upper: upper, fromStandaloneW: true))
                return true
            }
            return false
        }
        let bases = String(nuc.map { chars[$0].base })
        let hasFinal = (nuc.last! + 1) < chars.count

        // uo → ươ
        if let p = nuc.firstIndex(where: { i in chars[i].base == "u" && i + 1 < chars.count && chars[i + 1].base == "o" && nuc.contains(i + 1) }) {
            let u = nuc[p], o = u + 1
            if chars[u].mark == .horn && chars[o].mark == .horn {
                if chars[u].fromStandaloneW { return false }
                chars[u].mark = .none
                chars[o].mark = .none
                return undo(appending: key, upper: upper)
            }
            chars[u].mark = .horn
            chars[o].mark = .horn
            return true
        }

        var idx: Int?
        if (bases == "ua" && !hasFinal) || bases == "uu" {
            idx = nuc.first
        } else {
            let allowed: Set<Character> = allowBreve ? ["o", "u", "a"] : ["o", "u"]
            idx = nuc.last(where: { allowed.contains(chars[$0].base) })
        }
        guard let i = idx else { return false }
        let newMark: Mark = chars[i].base == "a" ? .breve : .horn
        if chars[i].mark == newMark {
            if chars[i].fromStandaloneW {
                // "ww" → "w"
                chars.remove(at: i)
                return undo(appending: key, upper: upper)
            }
            chars[i].mark = .none
            return undo(appending: key, upper: upper)
        }
        chars[i].mark = newMark
        return true
    }

    private func applyStroke(key: Character, upper: Bool) -> Bool {
        guard let first = chars.first, first.base == "d", chars.count >= 1 else { return false }
        if first.mark == .stroke {
            chars[0].mark = .none
            return undo(appending: key, upper: upper)
        }
        chars[0].mark = .stroke
        return true
    }

    // MARK: - Cấu trúc âm tiết

    private struct Parts {
        var onset: Range<Int>
        var nucleus: Range<Int>
        var final: Range<Int>
    }

    private func split() -> Parts {
        var i = 0
        while i < chars.count && !chars[i].isVowel { i += 1 }
        let onsetStr = String(chars[0..<i].map { $0.base })
        if i < chars.count {
            if onsetStr == "q" && chars[i].base == "u" && chars[i].mark == .none {
                i += 1
            } else if onsetStr == "g" && chars[i].base == "i" && i + 1 < chars.count && chars[i + 1].isVowel {
                i += 1
            }
        }
        let onsetEnd = i
        while i < chars.count && chars[i].isVowel { i += 1 }
        return Parts(onset: 0..<onsetEnd, nucleus: onsetEnd..<i, final: i..<chars.count)
    }

    private func nucleus() -> [Int]? {
        let p = split()
        guard !p.nucleus.isEmpty else { return nil }
        if chars[p.final].contains(where: { $0.isVowel }) { return nil }
        return Array(p.nucleus)
    }

    private static let onsets: Set<String> = [
        "", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "ng", "ngh",
        "nh", "p", "ph", "q", "qu", "r", "s", "t", "th", "tr", "v", "x",
    ]
    private static let nuclei: Set<String> = [
        "a", "e", "i", "o", "u", "y",
        "ai", "ao", "au", "ay", "eo", "eu", "ia", "ie", "iu", "oa", "oe", "oi", "oo", "ua", "ue",
        "ui", "uo", "uu", "uy", "ye",
        "ieu", "oai", "oao", "oay", "oeo", "uay", "uoi", "uou", "uya", "uye", "uyu", "yeu",
    ]
    private static let nucleiWithFinal: Set<String> = [
        "a", "e", "i", "o", "u", "y", "oa", "oe", "ie", "ye", "ua", "ue", "uo", "uy", "uye", "oo",
    ]
    private static let finals: Set<String> = ["c", "ch", "m", "n", "ng", "nh", "p", "t"]

    private func isValidSyllable() -> Bool {
        if chars.contains(where: { !$0.base.isLetter }) { return false }
        let p = split()
        let onset = String(chars[p.onset].map { $0.mark == .stroke ? "đ" : $0.base })
        guard Self.onsets.contains(onset) else { return false }
        if p.nucleus.isEmpty { return p.final.isEmpty }
        if onset == "q" { return false }  // "q" chỉ đứng trước "u" (qu)
        let nuc = String(chars[p.nucleus].map { $0.base })
        guard Self.nuclei.contains(nuc) else { return false }
        if p.final.isEmpty { return true }
        let fin = String(chars[p.final].map { $0.base })
        return Self.finals.contains(fin) && Self.nucleiWithFinal.contains(nuc)
    }

    /// Vần đã có mũ/móc, dùng khi từ đã gõ xong. "ue", "uo" không mũ không còn hợp lệ ở đây
    /// ("que" đã tách "qu" làm phụ âm đầu).
    private static let openRimes: Set<String> = [
        "a", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
        "ai", "ao", "au", "âu", "ay", "ây", "eo", "êu", "ia", "iu", "oa", "oe", "oi", "ôi", "ơi",
        "ua", "uê", "ui", "ưa", "ưi", "ưu", "uy", "uơ",
        "iêu", "yêu", "oai", "oao", "oay", "oeo", "uây", "uôi", "ươi", "ươu", "uya", "uyu",
    ]
    private static let closedRimes: Set<String> = [
        "a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư",
        "oa", "oă", "oe", "uâ", "uê", "uy", "iê", "yê", "uô", "ươ", "oo", "uyê",
    ]
    /// "ch", "nh" chỉ đứng sau những vần này (ách, ếch, ích, oách, uếch, uých).
    private static let palatalRimes: Set<String> = ["a", "ê", "i", "oa", "uê", "uy"]

    private static func markedVowel(_ c: VChar) -> Character {
        vowelVariant(c).map { vowelRows[$0][0][0] } ?? c.base
    }

    /// Kiểm chặt khi từ đã gõ xong: vần phải có thật (tính cả mũ/móc), và vần kết thúc bằng
    /// c, ch, p, t không mang dấu huyền, hỏi, ngã.
    private func isCompleteSyllable() -> Bool {
        guard isValidSyllable() else { return false }
        let p = split()
        if p.nucleus.isEmpty { return true }  // chỉ có phụ âm, vd "đ"
        var rime = String(chars[p.nucleus].map { Self.markedVowel($0) })
        // "qu" đã lấy mất "u" của vần "uy": quýt, quỳnh, quých
        if p.onset.count == 2 && chars[0].base == "q" && rime.first == "y" { rime = "u" + rime }
        if p.final.isEmpty { return Self.openRimes.contains(rime) }
        guard Self.closedRimes.contains(rime) else { return false }
        let fin = String(chars[p.final].map { $0.base })
        if (fin == "ch" || fin == "nh") && !Self.palatalRimes.contains(rime) { return false }
        // Thiếu dấu ("đươc") thì để nguyên cho người dùng tự sửa; chỉ dấu sai ("tẽt") mới trả lại phím gốc
        if ["c", "ch", "p", "t"].contains(fin) { return tone == .none || tone == .sac || tone == .nang }
        return true
    }

    private func tonePosition() -> Int? {
        guard tone != .none, let nuc = nucleus() else { return nil }
        if nuc.count == 1 { return nuc[0] }
        if let marked = nuc.last(where: { chars[$0].mark != .none }) { return marked }
        if nuc.count >= 3 { return nuc[1] }
        let hasFinal = nuc[1] + 1 < chars.count
        if hasFinal { return nuc[1] }
        let pair = String(nuc.map { chars[$0].base })
        if modernToneStyle && ["oa", "oe", "uy"].contains(pair) { return nuc[1] }
        return nuc[0]
    }

    // MARK: - Hiển thị

    /// [biến thể nguyên âm][thường/HOA][thanh 0...5] — dựng một lần, đã chuẩn hoá NFC.
    private static let vowelRows: [[[Character]]] = [
        "aáàảãạ", "ăắằẳẵặ", "âấầẩẫậ", "eéèẻẽẹ", "êếềểễệ", "iíìỉĩị",
        "oóòỏõọ", "ôốồổỗộ", "ơớờởỡợ", "uúùủũụ", "ưứừửữự", "yýỳỷỹỵ",
    ].map { row in
        let lower = row.precomposedStringWithCanonicalMapping
        return [Array(lower), Array(lower.uppercased().precomposedStringWithCanonicalMapping)]
    }

    private static func vowelVariant(_ c: VChar) -> Int? {
        switch (c.base, c.mark) {
        case ("a", .breve): return 1
        case ("a", .circumflex): return 2
        case ("a", _): return 0
        case ("e", .circumflex): return 4
        case ("e", _): return 3
        case ("i", _): return 5
        case ("o", .circumflex): return 7
        case ("o", .horn): return 8
        case ("o", _): return 6
        case ("u", .horn): return 10
        case ("u", _): return 9
        case ("y", _): return 11
        default: return nil
        }
    }

    private func render() -> [Character] {
        let tonePos = tonePosition()
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        for i in chars.indices {
            let c = chars[i]
            if let v = Self.vowelVariant(c) {
                out.append(Self.vowelRows[v][c.upper ? 1 : 0][i == tonePos ? tone.rawValue : 0])
            } else if c.mark == .stroke {
                out.append(c.upper ? "Đ" : "đ")
            } else if c.upper, let a = c.base.asciiValue, a >= 97, a <= 122 {
                out.append(Character(Unicode.Scalar(a - 32)))
            } else {
                out.append(c.base)
            }
        }
        return out
    }

    private func rebuildRaw() {
        var keys: [Character] = []
        for c in chars {
            let base = c.upper ? Character(c.base.uppercased()) : c.base
            if c.fromStandaloneW {
                keys.append(c.upper ? "W" : "w")
                continue
            }
            keys.append(base)
            switch (c.mark, method) {
            case (.none, _): break
            case (.circumflex, .telex), (.circumflex, .simpleTelex): keys.append(c.base)
            case (.breve, .telex), (.horn, .telex), (.breve, .simpleTelex), (.horn, .simpleTelex): keys.append("w")
            case (.stroke, .telex), (.stroke, .simpleTelex), (.stroke, .viqr): keys.append("d")
            case (.circumflex, .vni): keys.append("6")
            case (.horn, .vni): keys.append("7")
            case (.breve, .vni): keys.append("8")
            case (.stroke, .vni): keys.append("9")
            case (.circumflex, .viqr): keys.append("^")
            case (.breve, .viqr): keys.append("(")
            case (.horn, .viqr): keys.append("+")
            }
        }
        if tone != .none {
            let i = tone.rawValue - 1
            switch method {
            case .telex, .simpleTelex: keys.append(["s", "f", "r", "x", "j"][i])
            case .vni: keys.append(Character(String(tone.rawValue)))
            case .viqr: keys.append(["'", "`", "?", "~", "."][i])
            }
        }
        raw = keys
    }

    private func commit() -> EditResult {
        let newScreen = render()
        var p = 0
        while p < screen.count && p < newScreen.count && screen[p] == newScreen[p] { p += 1 }
        let result = EditResult(backspaces: screen.count - p, text: String(newScreen[p...]))
        screen = newScreen
        return result
    }
}
