import AppKit
import ApplicationServices
import os

/// Ảnh chụp cài đặt mà luồng bắt phím cần — kiểu giá trị, đọc được từ mọi luồng.
struct HookConfig {
    var defaultMethod: InputMethod?
    var appMethods: [String: InputMethod?] = [:]
    var fixAutocompleteApps: Set<String> = []
    var modernToneStyle = true
    var autoRestoreEnglish = true
    var hotkey: Hotkey = .ctrlShift

    func method(for bundleID: String?) -> InputMethod? {
        if let id = bundleID, let m = appMethods[id] { return m }
        return defaultMethod
    }
}

/// Bắt phím toàn hệ thống bằng CGEventTap, gửi Backspace + ký tự Unicode thay vì dùng
/// "marked text" (chữ gạch chân) như bộ gõ mặc định — nên không bị lặp chữ khi ứng dụng
/// tự gợi ý hoặc tự xoá vùng đang soạn.
///
/// Hiệu năng:
/// - Các tap chạy trên một luồng riêng ưu tiên cao: menu/cửa sổ cài đặt bận cũng không làm trễ phím.
/// - Không có timer định kỳ: ứng dụng đang nhận phím chỉ được đọc lại khi có sự kiện
///   (đổi app, click, ⌘/⌃/⌥, Esc/Return…), nên lúc rảnh app không thức dậy.
///
/// An toàn hệ thống (tránh treo máy):
/// - Tap chủ động (có thể chặn phím) CHỈ nhận keyDown. Chuột và phím bổ trợ đi qua tap listen-only.
/// - Callback không gọi Accessibility / IPC. Việc đọc AX chạy ở hàng đợi nền.
/// - `stop()` gỡ hẳn tap; AppDelegate gọi ngay khi phát hiện mất quyền Trợ năng.
final class KeyboardHook {
    private static let syntheticMarker: Int64 = 0x564E_4B45_59  // đánh dấu sự kiện do app tự gửi
    private static let deleteKeyCode: CGKeyCode = 51
    private static let spaceKeyCode: Int64 = 49
    private static let zKeyCode: Int64 = 6
    private static let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// Trạng thái dùng chung giữa luồng chính, luồng bắt phím và hàng đợi đọc AX.
    private struct Shared {
        var config: HookConfig
        var contextBundleID: String?
        var frontmostBundleID: String?
        var resetGeneration = 0
    }

    private let shared: OSAllocatedUnfairLock<Shared>

    // Chỉ dùng trên luồng bắt phím
    private let engine = VietnameseEngine()
    private let source = CGEventSource(stateID: .privateState)
    private var seenResetGeneration = -1
    private var config: HookConfig
    private var contextID: String?
    private var modifierHotkeyArmed = false
    private var lastContextRequest: TimeInterval = 0

    // Chỉ dùng trên contextQueue
    private var lastContextRead: TimeInterval = 0

    // Chỉ dùng trên luồng chính
    private var keyTap: CFMachPort?
    private var listenTap: CFMachPort?
    private var tapRunLoop: CFRunLoop?

    private let contextQueue = DispatchQueue(label: "vn.goviet.context", qos: .userInitiated)

    /// Gọi trên luồng chính khi người dùng nhấn phím tắt đảo Việt/Anh, kèm bundle ID của app đang nhận phím.
    var onToggle: ((String?) -> Void)?

    init(config: HookConfig) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        self.config = config
        shared = OSAllocatedUnfairLock(initialState: Shared(config: config, contextBundleID: front,
                                                            frontmostBundleID: front))
    }

    var isInstalled: Bool { keyTap != nil }

    func start() -> Bool {
        if keyTap != nil { return true }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let keyCallback: CGEventTapCallBack = { proxy, type, event, refcon in
            let hook = Unmanaged<KeyboardHook>.fromOpaque(refcon!).takeUnretainedValue()
            return hook.handleKey(proxy: proxy, type: type, event: event)
        }
        guard let keyTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                             options: .defaultTap,
                                             eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                                             callback: keyCallback, userInfo: refcon) else {
            return false
        }

        let listenMask: CGEventMask = [CGEventType.flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(0) { $0 | (1 << $1.rawValue) }
        let listenCallback: CGEventTapCallBack = { _, type, event, refcon in
            let hook = Unmanaged<KeyboardHook>.fromOpaque(refcon!).takeUnretainedValue()
            hook.handlePassive(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        let listenTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                          options: .listenOnly, eventsOfInterest: listenMask,
                                          callback: listenCallback, userInfo: refcon)
        self.keyTap = keyTap
        self.listenTap = listenTap

        let taps = [keyTap, listenTap].compactMap { $0 }
        let ready = DispatchSemaphore(value: 0)
        var runLoop: CFRunLoop?
        let thread = Thread {
            runLoop = CFRunLoopGetCurrent()
            for tap in taps {
                CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            ready.signal()
            CFRunLoopRun()  // kết thúc khi stop() gọi CFRunLoopStop
        }
        thread.name = "GoViet.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        tapRunLoop = runLoop
        requestContextRefresh(fromTapThread: false)
        return true
    }

    /// Gỡ hẳn các tap khỏi hệ thống và dừng luồng bắt phím.
    func stop() {
        for tap in [keyTap, listenTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let rl = tapRunLoop { CFRunLoopStop(rl) }
        keyTap = nil
        listenTap = nil
        tapRunLoop = nil
        shared.withLock { $0.resetGeneration += 1 }
    }

    func update(config: HookConfig) {
        shared.withLock {
            $0.config = config
            $0.resetGeneration += 1
        }
    }

    /// Gọi trên luồng chính khi ứng dụng frontmost đổi.
    func frontmostChanged(to bundleID: String?) {
        shared.withLock {
            $0.frontmostBundleID = bundleID
            $0.contextBundleID = bundleID
            $0.resetGeneration += 1
        }
        requestContextRefresh(fromTapThread: false)
    }

    // MARK: - Xử lý sự kiện (luồng bắt phím)

    /// Tap listen-only: không thể chặn sự kiện, nên dù chậm cũng không làm treo chuột/bàn phím.
    private func handlePassive(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            DispatchQueue.main.async { [weak self] in
                guard let tap = self?.listenTap, AXIsProcessTrusted() else { return }
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            engine.reset()
            requestContextRefresh(after: 0.05)
        case .flagsChanged:
            handleModifierHotkey(event.flags.intersection(Self.modifierMask))
        default:
            break
        }
    }

    private func handleKey(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        guard type == .keyDown else {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                engine.reset()
                // Bật lại trễ một nhịp, và chỉ khi vẫn còn quyền — tránh vòng lặp treo.
                DispatchQueue.main.async { [weak self] in
                    guard let tap = self?.keyTap, AXIsProcessTrusted() else { return }
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return pass
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return pass }
        modifierHotkeyArmed = false

        syncShared()
        let config = self.config, contextID = self.contextID

        let flags = event.flags.intersection(Self.modifierMask)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if isHotkey(config.hotkey, keyCode: keyCode, flags: flags) {
            engine.reset()
            DispatchQueue.main.async { [weak self] in self?.onToggle?(contextID) }
            return nil
        }

        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            // ⌘Space (Spotlight), ⌘Tab… có thể đổi nơi nhận phím; cửa sổ mới hiện ra sau một nhịp.
            engine.reset()
            requestContextRefresh(after: 0.15)
            requestContextRefresh(after: 0.6)
            return pass
        }

        if keyCode == Int64(Self.deleteKeyCode) {
            if !engine.backspace() { engine.reset() }
            return pass
        }

        var length = 0
        var unit: UniChar = 0
        event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &length, unicodeString: &unit)
        guard length == 1, unit < 0x80, let scalar = Unicode.Scalar(unit) else {
            // Esc, Return, Tab, phím mũi tên, ký tự ngoài ASCII… — có thể đóng Spotlight hoặc chuyển ô nhập
            engine.reset()
            requestContextRefresh(after: 0.15)
            return pass
        }
        let ch = Character(scalar)

        if engine.isEmpty {
            // Lưới an toàn: đầu mỗi từ, nếu lâu chưa đọc lại ngữ cảnh thì đọc (không chặn phím này).
            if ProcessInfo.processInfo.systemUptime - lastContextRequest > 5 { requestContextRefresh() }
        }

        guard let method = config.method(for: contextID) else {
            engine.reset()
            return pass
        }
        if engine.method != method { engine.reset(); engine.method = method }
        engine.modernToneStyle = config.modernToneStyle
        engine.autoRestoreEnglish = config.autoRestoreEnglish

        guard let result = engine.process(ch) else {
            engine.reset()
            return pass
        }
        if result.backspaces == 0 && result.text.utf8.count == 1 && result.text.utf8.first == UInt8(unit) {
            return pass  // không đổi gì — để phím gốc đi qua, ổn định nhất
        }
        let fix = contextID.map { config.fixAutocompleteApps.contains($0) } ?? false
        send(result, fixAutocomplete: fix, proxy: proxy)
        return nil
    }

    /// Chỉ chép cài đặt/ngữ cảnh khi chúng đổi (mọi thay đổi đều tăng resetGeneration),
    /// nên mỗi phím chỉ tốn một lần khoá + so sánh số nguyên.
    private func syncShared() {
        let seen = seenResetGeneration
        guard let snap = shared.withLock({ s -> (HookConfig, String?, Int)? in
            s.resetGeneration == seen ? nil : (s.config, s.contextBundleID, s.resetGeneration)
        }) else { return }
        (config, contextID, seenResetGeneration) = snap
        engine.reset()
    }

    private func isHotkey(_ hotkey: Hotkey, keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch hotkey {
        case .ctrlShift: return false
        case .optionZ: return keyCode == Self.zKeyCode && flags == .maskAlternate
        case .ctrlSpace: return keyCode == Self.spaceKeyCode && flags == .maskControl
        case .cmdShiftSpace: return keyCode == Self.spaceKeyCode && flags == [.maskCommand, .maskShift]
        }
    }

    /// ⌃⇧: nhấn rồi thả mà không gõ phím nào khác thì mới đảo.
    private func handleModifierHotkey(_ flags: CGEventFlags) {
        syncShared()
        guard config.hotkey == .ctrlShift else { return }
        let contextID = self.contextID
        if flags == [.maskControl, .maskShift] {
            modifierHotkeyArmed = true
        } else if flags.isEmpty {
            if modifierHotkeyArmed {
                modifierHotkeyArmed = false
                engine.reset()
                DispatchQueue.main.async { [weak self] in self?.onToggle?(contextID) }
            }
        } else if !flags.isSubset(of: [.maskControl, .maskShift]) {
            modifierHotkeyArmed = false
        }
    }

    // MARK: - Ngữ cảnh ứng dụng

    /// Đọc ứng dụng đang nhận phím (Spotlight, Raycast… không phải frontmost app) ở hàng đợi nền.
    /// Nhiều yêu cầu dồn dập (giữ phím mũi tên, click liên tục) được gộp: trong 80 ms chỉ đọc AX một lần,
    /// để app đang treo (mỗi lần đọc chờ tới 0,1 s) không làm hàng đợi dồn ứ và ngữ cảnh bị trễ.
    private func requestContextRefresh(after delay: TimeInterval = 0, fromTapThread: Bool = true) {
        if fromTapThread {
            lastContextRequest = ProcessInfo.processInfo.systemUptime
        }
        contextQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.lastContextRead < 0.08 { return }
            self.lastContextRead = now
            let focused = Self.focusedBundleID()
            self.shared.withLock { s in
                let id = focused ?? s.frontmostBundleID
                if s.contextBundleID != id {
                    s.contextBundleID = id
                    s.resetGeneration += 1
                }
            }
        }
    }

    private static func focusedBundleID() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(value as! AXUIElement, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    // MARK: - Gửi phím

    private func send(_ result: EditResult, fixAutocomplete: Bool, proxy: CGEventTapProxy) {
        var backspaces = result.backspaces
        if backspaces > 0 && fixAutocomplete {
            // Gõ một ký tự "vô hại" để huỷ phần gợi ý đang bôi đen, rồi xoá luôn nó.
            postText("\u{202F}", proxy: proxy)
            backspaces += 1
        }
        for _ in 0..<backspaces {
            postKey(Self.deleteKeyCode, proxy: proxy)
        }
        if !result.text.isEmpty {
            postText(result.text, proxy: proxy)
        }
    }

    private func postKey(_ code: CGKeyCode, proxy: CGEventTapProxy) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = .maskNonCoalesced
            e.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            e.tapPostEvent(proxy)
        }
    }

    /// Mã phím đi kèm chữ Unicode. Mặc định 0 (phím A) như OpenKey. Nhưng nếu phím A vẫn đang
    /// được giữ (gõ nhanh "ma" + "f"), macOS bỏ sự kiện "nhấn xuống" thứ hai của cùng phím
    /// và chữ "à" biến mất (đã xác nhận bằng KeyProbe). Khi đó dùng mã 0x46, không có trên bàn phím.
    private static func textKeyCode() -> CGKeyCode {
        CGEventSource.keyState(.hidSystemState, key: 0) ? 0x46 : 0
    }

    /// Chữ gửi bằng mã phím ở trên + chuỗi Unicode (giống OpenKey). Không dùng mã phím thật
    /// của chữ cái: nhiều ứng dụng dịch lại từ mã phím và gõ ra chữ gốc (vd "ư" thành "w").
    /// Cờ phải giữ NonCoalesced, nếu xoá sạch hệ thống có thể gộp/bỏ phím gửi liên tiếp.
    private func postText(_ text: String, proxy: CGEventTapProxy) {
        let units = Array(text.utf16)
        let keyCode = Self.textKeyCode()
        var start = 0
        while start < units.count {
            // Không cắt đôi cặp surrogate
            var end = min(start + 16, units.count)
            if end < units.count && UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            var chunk = Array(units[start..<end])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
                e.flags = .maskNonCoalesced
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                e.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
                e.tapPostEvent(proxy)
            }
            start = end
        }
    }
}
