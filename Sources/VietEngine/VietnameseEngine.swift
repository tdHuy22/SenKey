import Foundation

public enum InputMethod: String, Codable, CaseIterable {
    case telex, vni

    public var displayName: String { self == .telex ? "Telex" : "VNI" }
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
        let isLetter = key.isLetter
        let isDigit = key.isNumber
        if !(isLetter || (isDigit && method == .vni && !chars.isEmpty)) {
            return nil
        }

        let lower = Character(key.lowercased())
        let upper = key.isUppercase
        raw.append(key)

        if locked {
            chars.append(VChar(base: lower, upper: upper))
        } else {
            let handled = method == .telex ? applyTelex(lower, upper: upper) : applyVNI(lower, upper: upper)
            if !handled {
                chars.append(VChar(base: lower, upper: upper))
            }
            if !locked && autoRestoreEnglish && !isValidSyllable() && render() != raw {
                chars = raw.map { VChar(base: Character($0.lowercased()), upper: $0.isUppercase) }
                tone = .none
                locked = true
            }
        }
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
        case "w": return applyHorn(key: k, upper: upper, allowBreve: true, standalone: true)
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
            case (.circumflex, .telex): keys.append(c.base)
            case (.breve, .telex), (.horn, .telex): keys.append("w")
            case (.stroke, .telex): keys.append("d")
            case (.circumflex, .vni): keys.append("6")
            case (.horn, .vni): keys.append("7")
            case (.breve, .vni): keys.append("8")
            case (.stroke, .vni): keys.append("9")
            }
        }
        if tone != .none {
            let telex: [Character] = ["s", "f", "r", "x", "j"]
            keys.append(method == .telex ? telex[tone.rawValue - 1] : Character(String(tone.rawValue)))
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
