import AppKit
import ServiceManagement
import SwiftUI

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

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var loginItem: LoginItemModel

    private var sortedRules: [(id: String, rule: AppRule)] {
        settings.rules.map { ($0.key, $0.value) }
            .sorted { $0.rule.name.localizedCaseInsensitiveCompare($1.rule.name) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section("Chung") {
                Picker("Kiểu gõ mặc định", selection: $settings.defaultMethod) {
                    Text("Telex").tag(InputMethodChoice.telex)
                    Text("VNI").tag(InputMethodChoice.vni)
                }
                Toggle("Bật tiếng Việt cho ứng dụng chưa cài đặt", isOn: $settings.vietnameseByDefault)
                Toggle("Đặt dấu kiểu mới (hoà, thuỷ, khoẻ)", isOn: $settings.modernToneStyle)
                Toggle("Tự khôi phục từ tiếng Anh (windows, google…)", isOn: $settings.autoRestoreEnglish)
                Picker("Phím tắt đảo Việt/Anh", selection: $settings.hotkey) {
                    ForEach(Hotkey.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Khởi động cùng macOS", isOn: Binding(
                    get: { loginItem.enabled },
                    set: { loginItem.set($0) }
                ))
                if let loginError = loginItem.error {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

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
                Text("\"Sửa gợi ý\" tránh lỗi lặp chữ ở thanh địa chỉ trình duyệt, Spotlight, Excel… Mặc định đã bật cho các ứng dụng phổ biến.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 480)
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
