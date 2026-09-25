import AppKit
import Combine

enum AppMode: String, Codable, CaseIterable, Identifiable {
    case followDefault, telex, vni, english

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .followDefault: return "Theo mặc định"
        case .telex: return "Telex"
        case .vni: return "VNI"
        case .english: return "Tiếng Anh (tắt)"
        }
    }
}

struct AppRule: Codable, Equatable {
    var name: String
    var mode: AppMode = .followDefault
    /// nil = theo danh sách mặc định (trình duyệt, Spotlight…)
    var fixAutocomplete: Bool?
}

enum Hotkey: String, Codable, CaseIterable, Identifiable {
    case ctrlShift, optionZ, ctrlSpace, cmdShiftSpace

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ctrlShift: return "⌃⇧ (Control + Shift)"
        case .optionZ: return "⌥Z"
        case .ctrlSpace: return "⌃Space"
        case .cmdShiftSpace: return "⌘⇧Space"
        }
    }
}

private struct StoredSettings: Codable {
    var defaultMethod: InputMethodChoice = .telex
    var vietnameseByDefault = true
    var modernToneStyle = true
    var autoRestoreEnglish = true
    var hotkey: Hotkey = .ctrlShift
    var rules: [String: AppRule] = [:]
}

enum InputMethodChoice: String, Codable, CaseIterable, Identifiable {
    case telex, vni
    var id: String { rawValue }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private static let key = "SenKey.settings.v1"

    /// Ứng dụng có ô tự gợi ý (autocomplete) — dễ bị lỗi lặp chữ nếu không xử lý riêng.
    static let autocompleteApps: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "company.thebrowser.dia", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.kagi.kagimacOS", "app.zen-browser.zen",
        "com.coccoc.Coccoc", "com.apple.Spotlight", "com.raycast.macos", "com.runningwithcrayons.Alfred",
        "com.microsoft.Excel",
    ]

    @Published var defaultMethod: InputMethodChoice { didSet { save() } }
    @Published var vietnameseByDefault: Bool { didSet { save() } }
    @Published var modernToneStyle: Bool { didSet { save() } }
    @Published var autoRestoreEnglish: Bool { didSet { save() } }
    @Published var hotkey: Hotkey { didSet { save() } }
    @Published var rules: [String: AppRule] { didSet { save() } }

    private init() {
        var s = StoredSettings()
        // Lần đầu chạy sau khi đổi tên: lấy cài đặt cũ của GoViet (vn.goviet.app).
        let legacy = UserDefaults(suiteName: "vn.goviet.app")?.data(forKey: "GoViet.settings.v1")
        if let data = UserDefaults.standard.data(forKey: Self.key) ?? legacy,
           let decoded = try? JSONDecoder().decode(StoredSettings.self, from: data) {
            s = decoded
        }
        defaultMethod = s.defaultMethod
        vietnameseByDefault = s.vietnameseByDefault
        modernToneStyle = s.modernToneStyle
        autoRestoreEnglish = s.autoRestoreEnglish
        hotkey = s.hotkey
        rules = s.rules
    }

    private func save() {
        let s = StoredSettings(defaultMethod: defaultMethod, vietnameseByDefault: vietnameseByDefault,
                               modernToneStyle: modernToneStyle, autoRestoreEnglish: autoRestoreEnglish,
                               hotkey: hotkey, rules: rules)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    var defaultInputMethod: InputMethod { defaultMethod == .telex ? .telex : .vni }

    /// nil = gõ tiếng Anh (không xử lý).
    func method(for bundleID: String?) -> InputMethod? {
        let mode = bundleID.flatMap { rules[$0]?.mode } ?? .followDefault
        switch mode {
        case .followDefault: return vietnameseByDefault ? defaultInputMethod : nil
        case .telex: return .telex
        case .vni: return .vni
        case .english: return nil
        }
    }

    func fixAutocomplete(for bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return rules[id]?.fixAutocomplete ?? Self.autocompleteApps.contains(id)
    }

    /// Ảnh chụp cài đặt cho luồng bắt phím.
    func hookConfig() -> HookConfig {
        var c = HookConfig()
        c.defaultMethod = method(for: nil)
        for id in rules.keys { c.appMethods[id] = .some(method(for: id)) }
        c.fixAutocompleteApps = Self.autocompleteApps
        for (id, rule) in rules {
            if let fix = rule.fixAutocomplete {
                if fix { c.fixAutocompleteApps.insert(id) } else { c.fixAutocompleteApps.remove(id) }
            }
        }
        c.modernToneStyle = modernToneStyle
        c.autoRestoreEnglish = autoRestoreEnglish
        c.hotkey = hotkey
        return c
    }

    func mode(for bundleID: String) -> AppMode { rules[bundleID]?.mode ?? .followDefault }

    func setMode(_ mode: AppMode, for bundleID: String, name: String) {
        var rule = rules[bundleID] ?? AppRule(name: name)
        rule.name = name
        rule.mode = mode
        store(rule, for: bundleID)
    }

    func setFixAutocomplete(_ value: Bool, for bundleID: String, name: String) {
        var rule = rules[bundleID] ?? AppRule(name: name)
        rule.name = name
        rule.fixAutocomplete = value == Self.autocompleteApps.contains(bundleID) ? nil : value
        store(rule, for: bundleID)
    }

    /// Phím tắt: đảo Việt/Anh cho riêng ứng dụng hiện tại và ghi nhớ.
    func toggle(for bundleID: String, name: String) {
        let defaultMode: AppMode = vietnameseByDefault ? .followDefault : (defaultMethod == .telex ? .telex : .vni)
        let englishMode: AppMode = vietnameseByDefault ? .english : .followDefault
        setMode(method(for: bundleID) == nil ? defaultMode : englishMode, for: bundleID, name: name)
    }

    private func store(_ rule: AppRule, for bundleID: String) {
        if rule.mode == .followDefault && rule.fixAutocomplete == nil {
            rules.removeValue(forKey: bundleID)
        } else {
            rules[bundleID] = rule
        }
    }
}
