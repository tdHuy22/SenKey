import Foundation

/// Phím tắt người dùng tự ghi. `keyCode == nil`: chỉ gồm phím bổ trợ, nhấn rồi thả (vd ⌃⇧).
/// Cờ bổ trợ dùng đúng giá trị bit của CGEventFlags / NSEvent.ModifierFlags.
public struct HotkeySpec: Codable, Equatable {
    public static let shift: UInt64 = 1 << 17
    public static let control: UInt64 = 1 << 18
    public static let option: UInt64 = 1 << 19
    public static let command: UInt64 = 1 << 20
    public static let allModifiers = shift | control | option | command

    public var keyCode: Int?
    public var modifiers: UInt64
    /// Tên phím để hiển thị (vd "Z", "Space"), lấy lúc ghi phím.
    public var keyLabel: String

    public init(keyCode: Int?, modifiers: UInt64, keyLabel: String = "") {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.allModifiers
        self.keyLabel = keyLabel
    }

    /// Hợp lệ khi có ít nhất một phím bổ trợ; loại chỉ-bổ-trợ cần ít nhất hai (một phím đơn lẻ như ⇧
    /// được nhấn suốt khi gõ, không dùng làm phím tắt được).
    public var isValid: Bool {
        let count = [Self.shift, Self.control, Self.option, Self.command].filter { modifiers & $0 != 0 }.count
        return keyCode == nil ? count >= 2 : count >= 1
    }

    public var displayName: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return keyCode == nil ? s : s + keyLabel
    }

    /// Phím thường kèm đúng các phím bổ trợ này.
    public func matches(keyCode code: Int, modifiers flags: UInt64) -> Bool {
        keyCode == code && flags & Self.allModifiers == modifiers
    }
}

/// So sánh số phiên bản dạng "1.2.3" hoặc "v1.2.3".
public enum AppVersion {
    public static func parse(_ s: String) -> [Int] {
        let trimmed = s.hasPrefix("v") || s.hasPrefix("V") ? String(s.dropFirst()) : s
        return trimmed.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parse(candidate), b = parse(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
