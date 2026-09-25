import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private lazy var hook = KeyboardHook(config: settings.hookConfig())
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?
    private var accessibilityObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?

    /// Ứng dụng người dùng đang làm việc (không tính chính GoViet).
    private var targetApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        targetApp = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if app.bundleIdentifier != Bundle.main.bundleIdentifier { self.targetApp = app }
                self.hook.frontmostChanged(to: app.bundleIdentifier)
                self.updateStatusIcon()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.hook.update(config: self.settings.hookConfig())
                self.updateStatusIcon()
            }
            .store(in: &cancellables)

        hook.onToggle = { [weak self] bundleID in
            guard let self else { return }
            let id = bundleID ?? self.targetApp?.bundleIdentifier
            guard let id else { return }
            self.settings.toggle(for: id, name: Self.appName(for: id))
            NSSound(named: "Tink")?.play()
        }

        startHookOrWaitForPermission()
        updateStatusIcon()
    }

    // MARK: - Quyền Trợ năng

    private func startHookOrWaitForPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        permissionTimer?.invalidate()
        // Kiểm tra quyền mỗi giây (AXIsProcessTrusted chỉ tốn vài µs), có dung sai để macOS gộp lần thức dậy.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
        permissionTimer?.tolerance = 0.3
        if accessibilityObserver == nil {
            // Hệ thống phát thông báo này khi quyền Trợ năng thay đổi → phản ứng tức thì.
            accessibilityObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
            ) { [weak self] _ in
                self?.checkPermission()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.checkPermission() }
            }
        }
        checkPermission()
    }

    /// Chạy liên tục: bị tắt quyền Trợ năng → gỡ tap NGAY (tap còn đứng chặn luồng phím khi mất quyền
    /// có thể làm treo cả hệ thống). Được cấp lại → chờ một chút cho TCC ổn định rồi mới bật tap.
    private var trustedSince: Date?

    private func checkPermission() {
        if AXIsProcessTrusted() {
            if trustedSince == nil { trustedSince = Date() }
            if !hook.isInstalled, Date().timeIntervalSince(trustedSince!) >= 1.5 {
                _ = hook.start()
                updateStatusIcon()
            }
        } else {
            trustedSince = nil
            if hook.isInstalled {
                hook.stop()
                updateStatusIcon()
            }
        }
    }

    // MARK: - Menu bar

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let text: String
        if !hook.isInstalled {
            text = "⚠︎"
        } else {
            text = settings.method(for: targetApp?.bundleIdentifier) == nil ? "En" : "Vi"
        }
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
        ])
        button.toolTip = "GoViet"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !hook.isInstalled {
            menu.addItem(item("⚠︎ Cần cấp quyền Trợ năng — nhấn để mở", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        if let app = targetApp, let id = app.bundleIdentifier {
            let name = app.localizedName ?? id
            let method = settings.method(for: id)
            let header = NSMenuItem(title: "\(name): \(method.map { "Tiếng Việt – \($0.displayName)" } ?? "Tiếng Anh")",
                                    action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let toggle = item(method == nil ? "Bật tiếng Việt cho \(name)" : "Tắt tiếng Việt cho \(name)",
                              #selector(toggleCurrentApp))
            toggle.toolTip = "Phím tắt: \(settings.hotkey.displayName)"
            menu.addItem(toggle)

            let modeMenu = NSMenu()
            let currentMode = settings.mode(for: id)
            for mode in AppMode.allCases {
                let m = item(mode.displayName, #selector(setAppMode(_:)))
                m.representedObject = mode.rawValue
                m.state = mode == currentMode ? .on : .off
                modeMenu.addItem(m)
            }
            let modeItem = NSMenuItem(title: "Kiểu gõ cho \(name)", action: nil, keyEquivalent: "")
            modeItem.submenu = modeMenu
            menu.addItem(modeItem)

            let fix = item("Sửa lỗi lặp chữ ở ô gợi ý (trình duyệt…)", #selector(toggleFixAutocomplete))
            fix.state = settings.fixAutocomplete(for: id) ? .on : .off
            menu.addItem(fix)
            menu.addItem(.separator())
        }

        let defaultMenu = NSMenu()
        for choice in InputMethodChoice.allCases {
            let m = item(choice == .telex ? "Telex" : "VNI", #selector(setDefaultMethod(_:)))
            m.representedObject = choice.rawValue
            m.state = settings.defaultMethod == choice ? .on : .off
            defaultMenu.addItem(m)
        }
        let defaultItem = NSMenuItem(title: "Kiểu gõ mặc định", action: nil, keyEquivalent: "")
        defaultItem.submenu = defaultMenu
        menu.addItem(defaultItem)

        menu.addItem(checkbox("Bật tiếng Việt cho ứng dụng chưa cài đặt", settings.vietnameseByDefault,
                              #selector(toggleVietnameseByDefault)))
        menu.addItem(checkbox("Đặt dấu kiểu mới (hoà, thuỷ)", settings.modernToneStyle, #selector(toggleToneStyle)))
        menu.addItem(checkbox("Tự khôi phục từ tiếng Anh", settings.autoRestoreEnglish, #selector(toggleAutoRestore)))
        menu.addItem(.separator())
        menu.addItem(item("Cài đặt & danh sách ứng dụng…", #selector(openSettings), key: ","))
        menu.addItem(item("Thoát GoViet", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let m = NSMenuItem(title: title, action: action, keyEquivalent: key)
        m.target = self
        return m
    }

    private func checkbox(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let m = item(title, action)
        m.state = on ? .on : .off
        return m
    }

    static func appName(for bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    // MARK: - Hành động

    @objc private func toggleCurrentApp() {
        guard let id = targetApp?.bundleIdentifier else { return }
        settings.toggle(for: id, name: Self.appName(for: id))
    }

    @objc private func setAppMode(_ sender: NSMenuItem) {
        guard let id = targetApp?.bundleIdentifier,
              let raw = sender.representedObject as? String, let mode = AppMode(rawValue: raw) else { return }
        settings.setMode(mode, for: id, name: Self.appName(for: id))
    }

    @objc private func toggleFixAutocomplete() {
        guard let id = targetApp?.bundleIdentifier else { return }
        settings.setFixAutocomplete(!settings.fixAutocomplete(for: id), for: id, name: Self.appName(for: id))
    }

    @objc private func setDefaultMethod(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let c = InputMethodChoice(rawValue: raw) else { return }
        settings.defaultMethod = c
    }

    @objc private func toggleVietnameseByDefault() { settings.vietnameseByDefault.toggle() }
    @objc private func toggleToneStyle() { settings.modernToneStyle.toggle() }
    @objc private func toggleAutoRestore() { settings.autoRestoreEnglish.toggle() }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        startHookOrWaitForPermission()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "GoViet – Cài đặt"
            window.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, loginItem: LoginItemModel()))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
