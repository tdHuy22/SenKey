import AppKit
import Carbon
import SwiftUI

/// Trạng thái cửa sổ hướng dẫn cài đặt (ObservableObject thay cho @State để build được bằng Command Line Tools).
final class OnboardingModel: ObservableObject {
    @Published var trusted = AXIsProcessTrusted()
    @Published var conflicts: [String] = []
    @Published var tryText = ""
    let loginItem = LoginItemModel()
    var onOpenAccessibility: () -> Void = {}
    var onDone: () -> Void = {}

    init() { refresh() }

    func refresh() {
        let t = AXIsProcessTrusted()
        if t != trusted { trusted = t }
        let c = Self.findConflicts()
        if c != conflicts { conflicts = c }
    }

    func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    /// Bộ gõ tiếng Việt khác đang thực sự dùng: nguồn đầu vào đang chọn của macOS và các app bộ gõ phổ biến.
    /// Chỉ xét nguồn đang chọn: macOS có thể còn sót mục tiếng Việt trong danh sách dù người dùng không dùng.
    static func findConflicts() -> [String] {
        var names: [String] = []
        if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            let langs: [String] = property(current, kTISPropertyInputSourceLanguages) ?? []
            if langs.first == "vi" {
                let name: String = property(current, kTISPropertyLocalizedName) ?? "Tiếng Việt"
                names.append("\(name) của Apple")
            }
        }
        let known = ["EVKey", "OpenKey", "UniKey", "XKey", "GoTiengViet", "GõTiếngViệt", "Gox", "Laban Key"]
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName,
                  known.contains(where: { name.localizedCaseInsensitiveContains($0) }) else { continue }
            names.append(name)
        }
        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    private static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let p = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? T
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var loginItem: LoginItemModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Text("🪷").font(.system(size: 44))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Chào mừng đến với SenKey").font(.title2.bold())
                    Text(model.trusted ? "Xong rồi! Gõ thử ở ô bên dưới nhé." : "Làm theo các bước dưới đây để bắt đầu gõ tiếng Việt.")
                        .foregroundStyle(.secondary)
                }
            }

            StepRow(number: 1, done: model.trusted,
                    title: "Cho phép SenKey dùng bàn phím",
                    detail: model.trusted
                        ? "Đã cấp quyền."
                        : "Bấm nút bên phải. Trong danh sách Trợ năng, bật công tắc cạnh SenKey (có thể phải nhập mật khẩu máy).") {
                if !model.trusted {
                    Button("Mở Cài đặt") { model.onOpenAccessibility() }
                        .buttonStyle(.borderedProminent)
                }
            }

            StepRow(number: 2, done: model.conflicts.isEmpty,
                    title: "Không dùng cùng lúc bộ gõ khác",
                    detail: model.conflicts.isEmpty
                        ? "Không có bộ gõ nào khác đang dùng."
                        : "Đang dùng: \(model.conflicts.joined(separator: ", ")). Chuyển nguồn đầu vào về ABC hoặc thoát app bộ gõ đó, để chữ không bị xử lý hai lần.") {
                if !model.conflicts.isEmpty {
                    Button("Mở Bàn phím") { model.openKeyboardSettings() }
                }
            }

            StepRow(number: 3, done: loginItem.enabled,
                    title: "Tự mở SenKey khi bật máy",
                    detail: loginItem.error ?? "Không bắt buộc, nhưng tiện hơn.") {
                Toggle("", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.set($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Gõ thử").font(.headline)
                TextField(model.trusted ? "Ví dụ Telex: tieengs vieetj → tiếng việt" : "Cấp quyền ở bước 1 trước đã",
                          text: $model.tryText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!model.trusted)
                Text("Chữ **Vi / En** trên thanh menu (góc trên bên phải màn hình) là SenKey. Nhấn rồi thả **⌃ Control + ⇧ Shift** để đổi Việt ↔ Anh.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(model.trusted ? "Bắt đầu dùng" : "Để sau") { model.onDone() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

private struct StepRow<Accessory: View>: View {
    let number: Int
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor.opacity(0.15))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory()
        }
    }
}
