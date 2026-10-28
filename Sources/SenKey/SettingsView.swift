import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Trạng thái "Khởi động cùng macOS" (dùng ObservableObject thay cho @State để build được bằng Command Line Tools).
final class LoginItemModel: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled
    @Published var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "Không đặt được: \(error.localizedDescription). Hãy chép SenKey.app vào /Applications rồi thử lại."
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

/// Việc cửa sổ cài đặt nhờ AppDelegate làm.
struct SettingsActions {
    var checkForUpdates: () -> Void = {}
    var reportBug: () -> Void = {}
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var loginItem: LoginItemModel
    var actions = SettingsActions()
    // View gốc chỉ được tạo một lần, nên các model trạng thái sống ở đây (không dùng @State/@StateObject).
    private let draft = NewMacroModel()
    private let recorder = HotkeyRecorder()
    private let transfer = TransferModel()

    var body: some View {
        TabView {
            TypingTab(settings: settings)
                .tabItem { Label("Bộ gõ", systemImage: "keyboard") }
            MacroTab(settings: settings, draft: draft)
                .tabItem { Label("Gõ tắt", systemImage: "text.badge.plus") }
            AppsTab(settings: settings)
                .tabItem { Label("Ứng dụng", systemImage: "square.grid.2x2") }
            SystemTab(settings: settings, loginItem: loginItem, actions: actions, recorder: recorder, transfer: transfer)
                .tabItem { Label("Hệ thống", systemImage: "gearshape") }
        }
        .padding(.top, 8)
        .frame(minWidth: 640, minHeight: 540)
    }
}

// MARK: - Bộ gõ

private struct TypingTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section("Kiểu gõ") {
                Picker("Kiểu gõ mặc định", selection: $settings.defaultMethod) {
                    ForEach(InputMethodChoice.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Bật tiếng Việt cho ứng dụng chưa cài đặt", isOn: $settings.vietnameseByDefault)
                Toggle("Đặt dấu kiểu mới (hoà, thuỷ, khoẻ)", isOn: $settings.modernToneStyle)
            }
            Section {
                Toggle("Tự khôi phục từ tiếng Anh (windows, different, data…)", isOn: $settings.autoRestoreEnglish)
                Toggle("Esc trả lại phím gốc cho từ đang gõ (mĩ → mix)", isOn: $settings.escRestore)
                Picker("Nhấn rồi thả để gõ nguyên từ", selection: $settings.tempEnglishKey) {
                    ForEach(TempEnglishKey.allCases) { Text($0.displayName).tag($0) }
                }
            } header: {
                Text("Tiếng Anh")
            } footer: {
                Text("Nhấn rồi thả riêng phím này (không kèm phím khác): từ đang gõ trở về phím gốc, hoặc nếu chưa gõ gì thì từ kế tiếp được gõ nguyên phím, không thêm dấu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Quick Telex: cc → ch, gg → gi, kk → kh, nn → ng, qq → qu, pp → ph, tt → th", isOn: $settings.quickTelex)
                Toggle("Phụ âm đầu gõ tắt: f → ph, j → gi, w → qu", isOn: $settings.quickStartConsonant)
                Toggle("Phụ âm cuối gõ tắt: g → ng, h → nh, k → ch", isOn: $settings.quickEndConsonant)
                Toggle("Tự viết hoa chữ đầu câu", isOn: $settings.autoCapitalize)
            } header: {
                Text("Gõ nhanh")
            } footer: {
                Text("Phụ âm gõ tắt làm nhiều từ tiếng Anh bị đổi (for → phor), nên chỉ bật nếu bạn ít gõ tiếng Anh. Quick Telex chỉ áp dụng cho Telex.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Gõ tắt

/// Ô nhập mục gõ tắt mới (ObservableObject thay cho @State).
final class NewMacroModel: ObservableObject {
    @Published var abbreviation = ""
    @Published var text = ""
}

private struct MacroTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject var draft: NewMacroModel

    var body: some View {
        Form {
            Section {
                Toggle("Bật gõ tắt", isOn: $settings.macrosEnabled)
                Toggle("Dùng cả khi đang gõ tiếng Anh", isOn: $settings.macrosInEnglish)
                    .disabled(!settings.macrosEnabled)
                Toggle("Dùng cả trong Terminal và app dòng lệnh khác", isOn: $settings.macrosInTerminals)
                    .disabled(!settings.macrosEnabled)
            } footer: {
                Text("Gõ chữ viết tắt rồi nhấn Space, dấu câu hoặc Enter để thay. Nếu nhấn Enter, chữ được thay nhưng Enter chưa gửi đi: xem lại rồi nhấn Enter lần nữa. Chữ hoa theo chữ đã gõ: ko → không, Ko → Không, KO → KHÔNG. Trong chữ thay thế, {date} và {time} là ngày giờ hiện tại.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Thêm mục mới") {
                HStack {
                    TextField("Viết tắt (vd: ko)", text: $draft.abbreviation)
                        .frame(width: 150)
                    TextField("Thay bằng (vd: không)", text: $draft.text)
                    Button("Thêm") { add() }
                        .disabled(!canAdd)
                        .keyboardShortcut(.defaultAction)
                }
                if draft.abbreviation.contains(where: { $0.isWhitespace }) {
                    Text("Chữ viết tắt không được có khoảng trắng.").font(.caption).foregroundStyle(.red)
                } else if !Macro(abbreviation: draft.abbreviation, text: draft.text).isAllowed {
                    Text("Viết tắt tối đa \(Macro.maxAbbreviationLength) ký tự, chữ thay thế tối đa \(Macro.maxTextLength) ký tự, không có ký tự điều khiển.")
                        .font(.caption).foregroundStyle(.red)
                } else if draft.abbreviation.contains(where: { !$0.isASCII }) {
                    Text("Nên dùng chữ không dấu (dc thay vì đc): khi gõ, chữ có dấu có thể không hiện đúng như vậy.")
                        .font(.caption).foregroundStyle(.orange)
                } else if settings.macros.contains(where: { $0.abbreviation.lowercased() == draft.abbreviation.lowercased() }) {
                    Text("Đã có mục này; thêm nữa sẽ thay chữ của mục cũ.").font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Danh sách (\(settings.macros.count))") {
                if settings.macros.isEmpty {
                    Text("Chưa có mục nào.").foregroundStyle(.secondary)
                }
                ForEach(settings.macros) { macro in
                    HStack {
                        TextField("", text: binding(macro.id, \.abbreviation))
                            .frame(width: 150)
                        TextField("", text: binding(macro.id, \.text))
                        if !macro.isAllowed {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .help("Mục này đang tắt: có xuống dòng, Tab hay ký tự điều khiển, hoặc quá dài. Sửa lại để dùng.")
                        }
                        Button {
                            settings.macros.removeAll { $0.id == macro.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Xoá mục này")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var canAdd: Bool {
        let a = draft.abbreviation.trimmingCharacters(in: .whitespaces)
        return !a.isEmpty && !a.contains(where: { $0.isWhitespace }) && !draft.text.isEmpty
            && Macro(abbreviation: a, text: draft.text).isAllowed
    }

    private func add() {
        let abbr = draft.abbreviation.trimmingCharacters(in: .whitespaces)
        guard canAdd else { return }
        settings.macros.removeAll { $0.abbreviation.lowercased() == abbr.lowercased() }
        settings.macros.append(Macro(abbreviation: abbr, text: draft.text))
        settings.macros.sort { $0.abbreviation.localizedCaseInsensitiveCompare($1.abbreviation) == .orderedAscending }
        draft.abbreviation = ""
        draft.text = ""
    }

    private func binding(_ id: UUID, _ field: WritableKeyPath<Macro, String>) -> Binding<String> {
        Binding(
            get: { settings.macros.first(where: { $0.id == id })?[keyPath: field] ?? "" },
            set: { value in
                if let i = settings.macros.firstIndex(where: { $0.id == id }) { settings.macros[i][keyPath: field] = value }
            }
        )
    }
}

// MARK: - Ứng dụng

private struct AppsTab: View {
    @ObservedObject var settings: Settings

    private var sortedRules: [(id: String, rule: AppRule)] {
        settings.rules.map { ($0.key, $0.value) }
            .sorted { $0.rule.name.localizedCaseInsensitiveCompare($1.rule.name) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                if sortedRules.isEmpty {
                    Text("Chưa có ứng dụng nào. Dùng phím tắt trong một ứng dụng, hoặc thêm từ danh sách bên dưới.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedRules, id: \.id) { entry in
                    RuleRow(settings: settings, bundleID: entry.id, rule: entry.rule)
                }
                Menu("Thêm ứng dụng đang chạy…") {
                    ForEach(runningApps(), id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            guard let id = app.bundleIdentifier else { return }
                            settings.setMode(.english, for: id, name: app.localizedName ?? id)
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text("Theo ứng dụng")
            } footer: {
                Text("\"Sửa gợi ý\" tránh lỗi lặp chữ ở thanh địa chỉ trình duyệt, Spotlight, Excel… Mặc định đã bật cho các ứng dụng phổ biến. \"Từng phím\" gửi chữ từng ký tự một, cho ứng dụng gõ ra sai hoặc thiếu chữ.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && settings.rules[$0.bundleIdentifier!] == nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

private struct RuleRow: View {
    @ObservedObject var settings: Settings
    let bundleID: String
    let rule: AppRule

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon())
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.name)
                Text(bundleID).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { rule.mode },
                set: { settings.setMode($0, for: bundleID, name: rule.name) }
            )) {
                ForEach(AppMode.allCases) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .frame(width: 150)
            Toggle("Sửa gợi ý", isOn: Binding(
                get: { settings.fixAutocomplete(for: bundleID) },
                set: { settings.setFixAutocomplete($0, for: bundleID, name: rule.name) }
            ))
            .toggleStyle(.checkbox)
            Toggle("Từng phím", isOn: Binding(
                get: { settings.sendStepByStep(for: bundleID) },
                set: { settings.setSendStepByStep($0, for: bundleID, name: rule.name) }
            ))
            .toggleStyle(.checkbox)
            Button {
                settings.rules.removeValue(forKey: bundleID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Xoá cài đặt riêng")
        }
    }

    private func icon() -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - Hệ thống

/// Ghi phím tắt mới: bắt phím ngay trong cửa sổ cài đặt. Esc để huỷ.
final class HotkeyRecorder: ObservableObject {
    @Published var recording = false
    @Published var message: String?
    private var monitor: Any?
    private var heldModifiers: UInt64 = 0
    var onRecord: (HotkeySpec) -> Void = { _ in }

    func start() {
        guard monitor == nil else { return }
        recording = true
        message = nil
        heldModifiers = 0
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    private func handle(_ event: NSEvent) {
        let mods = UInt64(event.modifierFlags.intersection([.shift, .control, .option, .command]).rawValue)
        if event.type == .keyDown {
            heldModifiers = 0
            if event.keyCode == 53 && mods == 0 { stop(); return }  // Esc: huỷ
            let spec = HotkeySpec(keyCode: Int(event.keyCode), modifiers: mods, keyLabel: Self.label(event))
            if spec.isValid {
                onRecord(spec)
                stop()
            } else {
                message = "Cần kèm ⌃, ⌥ hoặc ⌘ (⇧ + chữ là gõ chữ hoa)."
            }
        } else if mods == 0 {
            // Thả hết phím bổ trợ mà chưa gõ phím nào: phím tắt chỉ gồm phím bổ trợ (vd ⌃⇧)
            let spec = HotkeySpec(keyCode: nil, modifiers: heldModifiers)
            heldModifiers = 0
            if spec.isValid {
                onRecord(spec)
                stop()
            } else if spec.modifiers != 0 {
                message = "Chỉ dùng phím bổ trợ thì cần ít nhất hai phím (vd ⌃⇧)."
            }
        } else {
            heldModifiers |= mods
        }
    }

    private static func label(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

private struct SystemTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject var loginItem: LoginItemModel
    let actions: SettingsActions
    @ObservedObject var recorder: HotkeyRecorder
    @ObservedObject var transfer: TransferModel

    var body: some View {
        Form {
            Section("Phím tắt đảo Việt/Anh") {
                Picker("Phím tắt", selection: $settings.hotkey) {
                    ForEach(Hotkey.allCases) { key in
                        Text(key == .custom ? "Tuỳ chỉnh: \(settings.customHotkey.displayName)" : key.displayName).tag(key)
                    }
                }
                HStack {
                    Button(recorder.recording ? "Nhấn phím tắt mới… (Esc để huỷ)" : "Ghi phím tắt tuỳ chỉnh…") {
                        recorder.onRecord = { spec in
                            settings.customHotkey = spec
                            settings.hotkey = .custom
                        }
                        if recorder.recording { recorder.stop() } else { recorder.start() }
                    }
                    if let message = recorder.message {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Section("Khởi động và cập nhật") {
                Toggle("Khởi động cùng macOS", isOn: Binding(
                    get: { loginItem.enabled },
                    set: { loginItem.set($0) }
                ))
                if let loginError = loginItem.error {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Tự kiểm tra bản mới mỗi ngày", isOn: $settings.autoCheckUpdates)
                Button("Kiểm tra bản mới ngay") { actions.checkForUpdates() }
            }
            Section {
                HStack {
                    Button("Xuất cài đặt…") { transfer.export(settings) }
                    Button("Nhập cài đặt…") { transfer.importSettings(into: settings) }
                }
                if let message = transfer.message {
                    Text(message).font(.caption).foregroundStyle(transfer.failed ? Color.red : Color.secondary)
                }
            } header: {
                Text("Sao lưu")
            } footer: {
                Text("File gồm mọi cài đặt, danh sách ứng dụng và gõ tắt, dùng để chuyển sang máy khác.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Báo lỗi…") { actions.reportBug() }
            } footer: {
                Text("Mở trang báo lỗi trên GitHub và chép sẵn thông tin máy, cài đặt chung (cả tên các ứng dụng có cài đặt riêng) và nhật ký sự kiện vào clipboard. Không gồm phím bạn gõ hay nội dung gõ tắt. Xem lại trước khi gửi.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.stop() }
    }
}

/// Xuất/nhập file cài đặt (ObservableObject thay cho @State).
final class TransferModel: ObservableObject {
    @Published var message: String?
    @Published var failed = false

    func export(_ settings: Settings) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SenKey-cai-dat.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.exportData().write(to: url, options: .atomic)
            report("Đã xuất ra \(url.lastPathComponent).", failed: false)
        } catch {
            report("Không xuất được: \(error.localizedDescription)", failed: true)
        }
    }

    func importSettings(into settings: Settings) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let imported: (settings: StoredSettings, droppedMacros: Int)
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Settings.maxImportSize else { throw CocoaError(.fileReadTooLarge) }
            imported = try Settings.readImport(Data(contentsOf: url))
        } catch {
            report("File không phải cài đặt SenKey hợp lệ. Cài đặt hiện tại giữ nguyên.", failed: true)
            return
        }
        // Gõ tắt trong file sẽ được SenKey gõ ra ở mọi app, nên cho người dùng thấy file làm gì trước khi áp dụng (TM-9, TM-10).
        let s = imported.settings
        let hotkey = s.hotkey == .custom ? s.customHotkey.displayName : s.hotkey.displayName
        var text = "Cài đặt hiện tại sẽ bị thay bằng nội dung file:\n"
            + "• \(s.macros.count) gõ tắt\(s.macrosInEnglish ? ", chạy cả khi gõ tiếng Anh" : "")\(s.macrosInTerminals ? ", CHẠY CẢ TRONG TERMINAL" : "")\n"
            + "• \(s.rules.count) ứng dụng có cài đặt riêng\n"
            + "• Phím tắt đảo Việt/Anh: \(hotkey)\n"
            + "• Tự kiểm tra bản mới: \(s.autoCheckUpdates ? "bật" : "TẮT")"
        if imported.droppedMacros > 0 {
            text += "\n\n\(imported.droppedMacros) gõ tắt bị bỏ vì có ký tự điều khiển (như xuống dòng) hoặc quá dài."
        }
        // Chỉ đếm số mục thì không thấy được mục kiểu "ls → curl … | sh", nên liệt kê từng mục, đánh dấu mục giống lệnh shell.
        let shell = CharacterSet(charactersIn: "|;&$`<>#")
        let suspicious = s.macros.filter { $0.text.rangeOfCharacter(from: shell) != nil }
        if !suspicious.isEmpty {
            text += "\n\n⚠️ \(suspicious.count) gõ tắt có ký tự hay dùng trong lệnh Terminal (| ; & $ ` < > #). Đọc kỹ danh sách bên dưới."
        }
        text += "\n\nChỉ nhập file bạn tin."
        let alert = NSAlert()
        alert.messageText = "Nhập cài đặt từ \(url.lastPathComponent)?"
        alert.informativeText = text
        if !s.macros.isEmpty {
            let list = s.macros.map { m -> String in
                let flag = suspicious.contains(m) ? "⚠️ " : ""
                let shown = m.text.count > 120 ? m.text.prefix(120) + "…" : Substring(m.text)
                return "\(flag)\(m.abbreviation) → \(shown)"
            }.joined(separator: "\n")
            let scroll = NSTextView.scrollableTextView()
            scroll.frame = NSRect(x: 0, y: 0, width: 440, height: 160)
            scroll.hasVerticalScroller = true
            if let view = scroll.documentView as? NSTextView {
                view.string = list
                view.isEditable = false
                view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            }
            alert.accessoryView = scroll
        }
        alert.addButton(withTitle: "Áp dụng")
        alert.addButton(withTitle: "Huỷ")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        settings.apply(s)
        report("Đã nhập cài đặt từ \(url.lastPathComponent).", failed: false)
    }

    private func report(_ text: String, failed: Bool) {
        message = text
        self.failed = failed
    }
}
