import Foundation

/// Một mục gõ tắt: gõ `abbreviation` rồi Space / dấu câu / Enter thì được thay bằng `text`.
public struct Macro: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var abbreviation: String
    public var text: String

    public init(abbreviation: String, text: String) {
        self.abbreviation = abbreviation
        self.text = text
    }
}

/// Tra và dựng chữ thay thế. Không phụ thuộc AppKit nên kiểm thử được độc lập.
public enum MacroExpander {
    /// Bảng tra: chữ viết tắt (chữ thường) → chữ thay thế. Mục trống hoặc có khoảng trắng bị bỏ qua.
    public static func table(_ macros: [Macro]) -> [String: String] {
        var t: [String: String] = [:]
        for m in macros {
            let key = m.abbreviation.lowercased()
            if !key.isEmpty, !m.text.isEmpty, !key.contains(where: { $0.isWhitespace }) { t[key] = m.text }
        }
        return t
    }

    /// Chữ thay thế cho từ vừa gõ, hoặc nil nếu không có mục nào khớp. Khớp hoa/thường theo từ đã gõ:
    /// "ko" → "không", "Ko" → "Không", "KO" → "KHÔNG". {date} và {time} được thay bằng ngày giờ hiện tại.
    public static func expand(_ word: String, table: [String: String], now: Date = Date()) -> String? {
        guard !word.isEmpty, let template = table[word.lowercased()] else { return nil }
        var text = fillPlaceholders(template, now: now)
        let letters = word.filter { $0.isLetter }
        if letters.count > 1 && letters.allSatisfy({ $0.isUppercase }) {
            text = text.uppercased()
        } else if let first = word.first, first.isUppercase, let t = text.first {
            text = t.uppercased() + text.dropFirst()
        }
        return text
    }

    static func fillPlaceholders(_ s: String, now: Date) -> String {
        guard s.contains("{") else { return s }
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM/yyyy"
        let date = f.string(from: now)
        f.dateFormat = "HH:mm"
        let time = f.string(from: now)
        return s.replacingOccurrences(of: "{date}", with: date).replacingOccurrences(of: "{time}", with: time)
    }
}

/// Theo dõi các ký tự vừa gõ để biết chữ cái kế tiếp có mở đầu câu không:
/// sau ". ", "? ", "! " hoặc sau Enter. Mọi thứ khác (chữ số, dấu khác, chữ cái) huỷ trạng thái chờ.
public struct SentenceCapitalizer {
    private enum State { case idle, afterTerminator, ready }
    private var state = State.idle

    public init() {}

    /// Không còn biết chắc chữ trước con trỏ là gì (click chuột, đổi app, phím mũi tên…).
    public mutating func reset() { state = .idle }

    /// Gọi trước khi gõ một chữ cái: true nếu chữ này cần viết hoa. Trạng thái chờ bị tiêu.
    public mutating func takeLetter() -> Bool {
        defer { state = .idle }
        return state == .ready
    }

    /// Gọi với mỗi ký tự không phải chữ cái vừa đi qua.
    public mutating func didType(_ ch: Character) {
        switch ch {
        case ".", "?", "!": state = .afterTerminator
        case " ": if state == .afterTerminator { state = .ready }
        case "\r", "\n": state = .ready
        default: state = .idle
        }
    }
}
