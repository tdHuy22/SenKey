import AppKit
import Combine

enum AppMode: String, Codable, CaseIterable, Identifiable {
    case followDefault, telex, simpleTelex, vni, viqr, english

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .followDefault: return "Theo mặc định"
        case .telex: return "Telex"
        case .simpleTelex: return "Simple Telex"
        case .vni: return "VNI"
        case .viqr: return "VIQR"
        case .english: return "Tiếng Anh (tắt)"
        }
    }
}

struct AppRule: Codable, Equatable {
    var name: String
    var mode: AppMode = .followDefault
    /// nil = theo danh sách mặc định (trình duyệt, Spotlight…)
    var fixAutocomplete: Bool?
    /// Gửi chữ từng ký tự một, cho ứng dụng nhận sai khi gửi cả cụm. nil = tắt.
    var sendStepByStep: Bool?
}

enum Hotkey: String, Codable, CaseIterable, Identifiable {
    case ctrlShift, optionZ, ctrlSpace, cmdShiftSpace, custom

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ctrlShift: return "⌃⇧ (Control + Shift)"
        case .optionZ: return "⌥Z"
        case .ctrlSpace: return "⌃Space"
        case .cmdShiftSpace: return "⌘⇧Space"
        case .custom: return "Tuỳ chỉnh"
        }
    }

    /// nil với .custom (dùng phím người dùng đã ghi).
    var preset: HotkeySpec? {
        switch self {
        case .ctrlShift: return HotkeySpec(keyCode: nil, modifiers: HotkeySpec.control | HotkeySpec.shift)
        case .optionZ: return HotkeySpec(keyCode: 6, modifiers: HotkeySpec.option, keyLabel: "Z")
        case .ctrlSpace: return HotkeySpec(keyCode: 49, modifiers: HotkeySpec.control, keyLabel: "Space")
        case .cmdShiftSpace: return HotkeySpec(keyCode: 49, modifiers: HotkeySpec.command | HotkeySpec.shift, keyLabel: "Space")
        case .custom: return nil
        }
    }
}

/// Nhấn rồi thả riêng phím này: từ đang gõ trả về phím gốc, hoặc từ kế tiếp gõ nguyên phím.
enum TempEnglishKey: String, Codable, CaseIterable, Identifiable {
    case off, option, control

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .off: return "Tắt"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        }
    }
    var modifiers: UInt64? {
        switch self {
        case .off: return nil
        case .option: return HotkeySpec.option
        case .control: return HotkeySpec.control
        }
    }
}

enum InputMethodChoice: String, Codable, CaseIterable, Identifiable {
    case telex, simpleTelex, vni, viqr
    var id: String { rawValue }
    var method: InputMethod { InputMethod(rawValue: rawValue) ?? .telex }
    var displayName: String { method.displayName }
}

/// Mọi cài đặt, đúng dạng lưu trong UserDefaults và trong file xuất/nhập.
/// Trường nào thiếu (dữ liệu từ bản cũ) thì lấy giá trị mặc định, không làm hỏng cả bộ cài đặt.
struct StoredSettings: Codable, Equatable {
    var defaultMethod: InputMethodChoice = .telex
    var vietnameseByDefault = true
    var modernToneStyle = true
    var autoRestoreEnglish = true
    var hotkey: Hotkey = .ctrlShift
    var customHotkey = HotkeySpec(keyCode: nil, modifiers: HotkeySpec.option | HotkeySpec.shift)
    var rules: [String: AppRule] = [:]
    var quickTelex = false
    var quickStartConsonant = false
    var quickEndConsonant = false
    var escRestore = true
    var tempEnglishKey: TempEnglishKey = .option
    var autoCapitalize = false
    var macrosEnabled = true
    var macrosInEnglish = true
    var macrosInTerminals = false
    var macros: [Macro] = []
    var autoCheckUpdates = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case defaultMethod, vietnameseByDefault, modernToneStyle, autoRestoreEnglish, hotkey, customHotkey, rules
        case quickTelex, quickStartConsonant, quickEndConsonant, escRestore, tempEnglishKey, autoCapitalize
        case macrosEnabled, macrosInEnglish, macrosInTerminals, macros, autoCheckUpdates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StoredSettings()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        defaultMethod = get(.defaultMethod, d.defaultMethod)
        vietnameseByDefault = get(.vietnameseByDefault, d.vietnameseByDefault)
        modernToneStyle = get(.modernToneStyle, d.modernToneStyle)
        autoRestoreEnglish = get(.autoRestoreEnglish, d.autoRestoreEnglish)
        hotkey = get(.hotkey, d.hotkey)
        customHotkey = get(.customHotkey, d.customHotkey).sanitized ?? d.customHotkey
        rules = get(.rules, d.rules)
        quickTelex = get(.quickTelex, d.quickTelex)
        quickStartConsonant = get(.quickStartConsonant, d.quickStartConsonant)
        quickEndConsonant = get(.quickEndConsonant, d.quickEndConsonant)
        escRestore = get(.escRestore, d.escRestore)
        tempEnglishKey = get(.tempEnglishKey, d.tempEnglishKey)
        autoCapitalize = get(.autoCapitalize, d.autoCapitalize)
        macrosEnabled = get(.macrosEnabled, d.macrosEnabled)
        macrosInEnglish = get(.macrosInEnglish, d.macrosInEnglish)
        macrosInTerminals = get(.macrosInTerminals, d.macrosInTerminals)
        // Mục không `isAllowed` vẫn giữ (gõ tắt nhiều dòng tạo ở 1.2.0) để người dùng tự sửa; bảng tra bỏ qua chúng.
        macros = get(.macros, d.macros)
        autoCheckUpdates = get(.autoCheckUpdates, d.autoCheckUpdates)
    }
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

    /// Ứng dụng terminal: gõ tắt bung ở đây là gõ lệnh, và Enter của người dùng sẽ chạy nó (TM-9),
    /// nên mặc định không bung gõ tắt trong các app này.
    static let terminalApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp-Preview",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty",
        "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby", "com.raphaelamorim.rio",
        // Điều khiển máy khác hay máy ảo: phím có thể vào terminal của máy đó.
        "com.apple.ScreenSharing", "com.microsoft.rdc.macos", "com.realvnc.rvncconnect",
        "com.utmapp.UTM", "com.parallels.desktop.console", "com.termius-dmg.mac", "com.p5sys.jump.mac.viewer.web",
    ]

    @Published var defaultMethod: InputMethodChoice { didSet { save() } }
    @Published var vietnameseByDefault: Bool { didSet { save() } }
    @Published var modernToneStyle: Bool { didSet { save() } }
    @Published var autoRestoreEnglish: Bool { didSet { save() } }
    @Published var hotkey: Hotkey { didSet { save() } }
    @Published var customHotkey: HotkeySpec { didSet { save() } }
    @Published var rules: [String: AppRule] { didSet { save() } }
    @Published var quickTelex: Bool { didSet { save() } }
    @Published var quickStartConsonant: Bool { didSet { save() } }
    @Published var quickEndConsonant: Bool { didSet { save() } }
    @Published var escRestore: Bool { didSet { save() } }
    @Published var tempEnglishKey: TempEnglishKey { didSet { save() } }
    @Published var autoCapitalize: Bool { didSet { save() } }
    @Published var macrosEnabled: Bool { didSet { save() } }
    @Published var macrosInEnglish: Bool { didSet { save() } }
    @Published var macrosInTerminals: Bool { didSet { save() } }
    @Published var macros: [Macro] { didSet { save() } }
    @Published var autoCheckUpdates: Bool { didSet { save() } }

    private var loading = false

    private init() {
        var s = StoredSettings()
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(StoredSettings.self, from: data) {
            s = decoded
        }
        defaultMethod = s.defaultMethod
        vietnameseByDefault = s.vietnameseByDefault
        modernToneStyle = s.modernToneStyle
        autoRestoreEnglish = s.autoRestoreEnglish
        hotkey = s.hotkey
        customHotkey = s.customHotkey
        rules = s.rules
        quickTelex = s.quickTelex
        quickStartConsonant = s.quickStartConsonant
        quickEndConsonant = s.quickEndConsonant
        escRestore = s.escRestore
        tempEnglishKey = s.tempEnglishKey
        autoCapitalize = s.autoCapitalize
        macrosEnabled = s.macrosEnabled
        macrosInEnglish = s.macrosInEnglish
        macrosInTerminals = s.macrosInTerminals
        macros = s.macros
        autoCheckUpdates = s.autoCheckUpdates
    }

    var stored: StoredSettings {
        var s = StoredSettings()
        s.defaultMethod = defaultMethod
        s.vietnameseByDefault = vietnameseByDefault
        s.modernToneStyle = modernToneStyle
        s.autoRestoreEnglish = autoRestoreEnglish
        s.hotkey = hotkey
        s.customHotkey = customHotkey
        s.rules = rules
        s.quickTelex = quickTelex
        s.quickStartConsonant = quickStartConsonant
        s.quickEndConsonant = quickEndConsonant
        s.escRestore = escRestore
        s.tempEnglishKey = tempEnglishKey
        s.autoCapitalize = autoCapitalize
        s.macrosEnabled = macrosEnabled
        s.macrosInEnglish = macrosInEnglish
        s.macrosInTerminals = macrosInTerminals
        s.macros = macros
        s.autoCheckUpdates = autoCheckUpdates
        return s
    }

    /// Thay toàn bộ cài đặt (nhập từ file). Chỉ lưu một lần ở cuối.
    func apply(_ s: StoredSettings) {
        loading = true
        defaultMethod = s.defaultMethod
        vietnameseByDefault = s.vietnameseByDefault
        modernToneStyle = s.modernToneStyle
        autoRestoreEnglish = s.autoRestoreEnglish
        hotkey = s.hotkey
        customHotkey = s.customHotkey
        rules = s.rules
        quickTelex = s.quickTelex
        quickStartConsonant = s.quickStartConsonant
        quickEndConsonant = s.quickEndConsonant
        escRestore = s.escRestore
        tempEnglishKey = s.tempEnglishKey
        autoCapitalize = s.autoCapitalize
        macrosEnabled = s.macrosEnabled
        macrosInEnglish = s.macrosInEnglish
        macrosInTerminals = s.macrosInTerminals
        macros = s.macros
        autoCheckUpdates = s.autoCheckUpdates
        loading = false
        save()
    }

    private func save() {
        guard !loading else { return }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: - Xuất / nhập

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(stored)
    }

    static let maxImportSize = 1_000_000

    /// Đọc file cài đặt để người dùng xem trước rồi mới `apply` (TM-9). File phải là JSON cài đặt SenKey, không quá
    /// `maxImportSize`; file hỏng thì báo lỗi. `droppedMacros`: số gõ tắt bị bỏ vì có ký tự điều khiển hoặc quá dài.
    static func readImport(_ data: Data) throws -> (settings: StoredSettings, droppedMacros: Int) {
        guard data.count <= maxImportSize,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["defaultMethod"] != nil || object["rules"] != nil || object["macros"] != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var settings = try JSONDecoder().decode(StoredSettings.self, from: data)
        let raw = settings.macros.count
        settings.macros = Array(settings.macros.filter(\.isAllowed).prefix(Macro.maxCount))
        return (settings, raw - settings.macros.count)
    }

    // MARK: - Tra cứu

    var defaultInputMethod: InputMethod { defaultMethod.method }

    var hotkeySpec: HotkeySpec { hotkey.preset ?? customHotkey }
    var hotkeyDisplayName: String { hotkeySpec.displayName }

    /// nil = gõ tiếng Anh (không xử lý).
    func method(for bundleID: String?) -> InputMethod? {
        let mode = bundleID.flatMap { rules[$0]?.mode } ?? .followDefault
        switch mode {
        case .followDefault: return vietnameseByDefault ? defaultInputMethod : nil
        case .telex: return .telex
        case .simpleTelex: return .simpleTelex
        case .vni: return .vni
        case .viqr: return .viqr
        case .english: return nil
        }
    }

    func fixAutocomplete(for bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return rules[id]?.fixAutocomplete ?? Self.autocompleteApps.contains(id)
    }

    func sendStepByStep(for bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return rules[id]?.sendStepByStep ?? false
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
            if rule.sendStepByStep == true { c.stepByStepApps.insert(id) }
        }
        c.modernToneStyle = modernToneStyle
        c.autoRestoreEnglish = autoRestoreEnglish
        c.hotkey = hotkeySpec
        c.quickTelex = quickTelex
        c.quickStartConsonant = quickStartConsonant
        c.quickEndConsonant = quickEndConsonant
        c.escRestore = escRestore
        c.tempEnglishModifiers = tempEnglishKey.modifiers
        c.autoCapitalize = autoCapitalize
        c.macros = macrosEnabled ? MacroExpander.table(macros) : [:]
        c.macrosInEnglish = macrosInEnglish
        if !macrosInTerminals { c.noMacroApps = Self.terminalApps }
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

    func setSendStepByStep(_ value: Bool, for bundleID: String, name: String) {
        var rule = rules[bundleID] ?? AppRule(name: name)
        rule.name = name
        rule.sendStepByStep = value ? true : nil
        store(rule, for: bundleID)
    }

    /// Phím tắt: đảo Việt/Anh cho riêng ứng dụng hiện tại và ghi nhớ.
    func toggle(for bundleID: String, name: String) {
        let defaultMode: AppMode = vietnameseByDefault ? .followDefault : AppMode(rawValue: defaultMethod.rawValue) ?? .telex
        let englishMode: AppMode = vietnameseByDefault ? .english : .followDefault
        setMode(method(for: bundleID) == nil ? defaultMode : englishMode, for: bundleID, name: name)
    }

    private func store(_ rule: AppRule, for bundleID: String) {
        if rule.mode == .followDefault && rule.fixAutocomplete == nil && rule.sendStepByStep == nil {
            rules.removeValue(forKey: bundleID)
        } else {
            rules[bundleID] = rule
        }
    }
}
