import AppKit
import os

/// Nhật ký sự kiện nội bộ (giữ 200 dòng gần nhất, chỉ trong bộ nhớ) để đính kèm khi báo lỗi.
/// TUYỆT ĐỐI không ghi phím gõ, chữ đang gõ hay nội dung gõ tắt: chỉ ghi sự kiện hệ thống
/// (tap bị tắt, quyền Trợ năng đổi, cập nhật…). Gọi được từ mọi luồng.
enum Log {
    private static let lines = OSAllocatedUnfairLock<[String]>(initialState: [])
    private static let limit = 200

    static func add(_ message: String) {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
        lines.withLock {
            $0.append("\(stamp) \(message)")
            if $0.count > limit { $0.removeFirst($0.count - limit) }
        }
    }

    static var recent: [String] { lines.withLock { $0 } }
}

/// Báo lỗi: dựng báo cáo (phiên bản, máy, cài đặt chung, nhật ký, crash gần nhất), chép vào clipboard
/// rồi mở trang tạo issue trên GitHub để người dùng xem lại và dán vào.
enum BugReport {
    static func make(settings: Settings, hookInstalled: Bool) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var arch = "?"
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #endif
        let s = settings
        var out = """
        ## Môi trường
        - SenKey \(version) (\(build)), \(arch)
        - macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Quyền Trợ năng: \(AXIsProcessTrusted() ? "có" : "không"), bộ bắt phím: \(hookInstalled ? "đang chạy" : "chưa chạy")

        ## Cài đặt (không gồm nội dung gõ tắt)
        - Kiểu gõ mặc định: \(s.defaultMethod.displayName), bật tiếng Việt mặc định: \(s.vietnameseByDefault)
        - Dấu kiểu mới: \(s.modernToneStyle), tự khôi phục tiếng Anh: \(s.autoRestoreEnglish)
        - Quick Telex: \(s.quickTelex), phụ âm đầu/cuối gõ tắt: \(s.quickStartConsonant)/\(s.quickEndConsonant)
        - Esc trả phím gốc: \(s.escRestore), phím gõ nguyên từ: \(s.tempEnglishKey.displayName), viết hoa đầu câu: \(s.autoCapitalize)
        - Phím tắt: \(s.hotkeyDisplayName), gõ tắt: \(s.macrosEnabled) (\(s.macros.count) mục)
        - Ứng dụng có cài đặt riêng:
        """
        for (id, rule) in s.rules.sorted(by: { $0.key < $1.key }) {
            out += "\n  - \(id): \(rule.mode.rawValue)"
            if let fix = rule.fixAutocomplete { out += ", sửa gợi ý: \(fix)" }
            if rule.sendStepByStep == true { out += ", gửi từng phím" }
        }
        out += "\n\n## Nhật ký gần đây\n```\n" + Log.recent.suffix(80).joined(separator: "\n") + "\n```\n"
        if let crash = latestCrash() {
            out += "\n## Crash gần nhất: \(crash.name)\n```\n\(crash.head)\n```\n"
        }
        return out
    }

    /// Báo cáo crash gần nhất của SenKey (chỉ 60 dòng đầu: loại lỗi, luồng hỏng).
    private static func latestCrash() -> (name: String, head: String)? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        let crashes = files.filter { $0.lastPathComponent.hasPrefix("SenKey") }
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        guard let latest = crashes.max(by: { date($0) < date($1) }),
              let text = try? String(contentsOf: latest, encoding: .utf8) else { return nil }
        return (latest.lastPathComponent, text.split(separator: "\n", omittingEmptySubsequences: false).prefix(60).joined(separator: "\n"))
    }

    static func open(settings: Settings, hookInstalled: Bool) {
        let report = make(settings: settings, hookInstalled: hookInstalled)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        let body = """
        **Mô tả lỗi:** (gõ gì, trong ứng dụng nào, thấy gì, mong đợi gì)


        **Thông tin máy:** SenKey đã chép sẵn báo cáo vào clipboard. Nhấn ⌘V vào đây, xem lại rồi xoá phần nào bạn không muốn công khai.
        """
        var c = URLComponents(string: "https://github.com/tdHuy22/SenKey/issues/new")!
        c.queryItems = [URLQueryItem(name: "body", value: body)]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}
