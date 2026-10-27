import AppKit

/// Tự cập nhật từ GitHub Releases, giữ đúng các chốt chặn của get.sh (TM-1, TM-2 trong .agent/threat-model.md):
/// bản tải về phải là thư mục thật, chữ ký nguyên vẹn và khớp yêu cầu ghim, yêu cầu gắn trong app cũng đúng
/// bằng nó. Sai ở bất kỳ bước nào thì dừng, bản đang cài không bị đụng. Chỉ gọi mạng tới api.github.com
/// và nơi GitHub lưu file phát hành; không gửi gì về phím gõ.
final class Updater {
    static let shared = Updater()

    /// Phải giống hệt REQUIREMENT trong get.sh (CI kiểm điều này).
    static let requirement = #"=identifier "vn.senkey.app" and certificate leaf = H"e90227565deafdcd07f260406f4934fe32ed72d6""#
    private static let latestURL = URL(string: "https://api.github.com/repos/tdHuy22/SenKey/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/tdHuy22/SenKey/releases/latest")!
    private static let lastCheckKey = "SenKey.update.lastCheck"

    private var busy = false

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
        let tagName: String
        let htmlUrl: URL
        let body: String?
        let assets: [Asset]
    }

    // MARK: - Kiểm tra

    /// Tự kiểm tối đa một lần mỗi ngày (gọi lúc mở app và theo bộ hẹn giờ).
    func checkIfDue() {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard !busy else { return }
        busy = true
        var request = URLRequest(url: Self.latestURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, error in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let release = data.flatMap { try? decoder.decode(Release.self, from: $0) }
            DispatchQueue.main.async {
                self.busy = false
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
                guard let release else {
                    Log.add("Kiểm tra cập nhật lỗi: \(error?.localizedDescription ?? "dữ liệu không đọc được")")
                    if userInitiated {
                        self.alert("Không kiểm tra được bản mới", "Hãy kiểm tra kết nối mạng rồi thử lại.")
                    }
                    return
                }
                self.offer(release, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func offer(_ release: Release, userInitiated: Bool) {
        guard AppVersion.isNewer(release.tagName, than: currentVersion) else {
            if userInitiated { alert("SenKey đã là bản mới nhất", "Bạn đang dùng SenKey \(currentVersion).") }
            return
        }
        Log.add("Có bản mới \(release.tagName)")
        let a = NSAlert()
        a.messageText = "Có SenKey \(release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))) mới"
        var notes = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.count > 700 { notes = String(notes.prefix(700)) + "…" }
        a.informativeText = "Bạn đang dùng bản \(currentVersion). SenKey sẽ tải bản mới, kiểm chữ ký rồi tự mở lại.\n\n\(notes)"
        a.addButton(withTitle: "Cập nhật")
        a.addButton(withTitle: "Để sau")
        a.addButton(withTitle: "Xem chi tiết")
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: install(release)
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.htmlUrl)
        default: break
        }
    }

    // MARK: - Cài đặt

    private func install(_ release: Release) {
        guard let asset = release.assets.first(where: { $0.name == "SenKey.zip" }) else {
            NSWorkspace.shared.open(release.htmlUrl)
            return
        }
        let current = Bundle.main.bundleURL
        // Bản tự build (ký ad-hoc hoặc chứng chỉ khác) mà thay bằng bản phát hành thì quyền Trợ năng không còn khớp;
        // việc đó cần thoát app và đặt lại quyền như get.sh làm, nên để get.sh lo.
        guard Self.verify(current) else {
            alert("Hãy cập nhật bằng lệnh cài đặt",
                  "SenKey đang chạy không phải bản phát hành chính thức (ví dụ bản tự build), nên không tự thay được. "
                  + "Mở Terminal và chạy lại lệnh cài trong README.")
            NSWorkspace.shared.open(Self.releasesPage)
            return
        }
        guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            alert("Không có quyền ghi", "SenKey không ghi được vào \(current.deletingLastPathComponent().path).")
            return
        }
        busy = true
        Log.add("Tải \(release.tagName)")
        URLSession.shared.downloadTask(with: asset.browserDownloadUrl) { file, _, error in
            // File tải về bị xoá khi hàm này trả về, nên chuyển đi ngay trên luồng này.
            var prepared: URL?
            var problem = error?.localizedDescription ?? "tải không thành công"
            if let file {
                do {
                    prepared = try Self.unpackAndVerify(zip: file)
                } catch {
                    problem = error.localizedDescription
                }
            }
            DispatchQueue.main.async {
                self.busy = false
                guard let prepared else {
                    Log.add("Cập nhật dừng: \(problem)")
                    self.alert("Không cập nhật được", "\(problem)\n\nBản đang dùng giữ nguyên.")
                    return
                }
                self.replaceAndRelaunch(current: current, with: prepared)
            }
        }.resume()
    }

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Giải nén vào thư mục tạm riêng và kiểm chữ ký. Trả về đường dẫn SenKey.app đã kiểm.
    private static func unpackAndVerify(zip: URL) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("SenKey-update-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zipCopy = dir.appendingPathComponent("SenKey.zip")
        try fm.moveItem(at: zip, to: zipCopy)
        let out = dir.appendingPathComponent("x")
        guard run("/usr/bin/ditto", ["-x", "-k", zipCopy.path, out.path]).status == 0 else {
            throw UpdateError("File tải về không giải nén được.")
        }
        let app = out.appendingPathComponent("SenKey.app")
        guard verify(app) else {
            throw UpdateError("Bản tải về không mang chữ ký của SenKey nên không được cài.")
        }
        return app
    }

    /// Giống verify_app trong get.sh: thư mục thật (không phải symlink), chữ ký nguyên vẹn và khớp yêu cầu ghim,
    /// yêu cầu gắn trong app đúng bằng yêu cầu ghim.
    static func verify(_ app: URL) -> Bool {
        let values = try? app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else { return false }
        guard run("/usr/bin/codesign", ["--verify", "--strict", "--deep", "-R", requirement, app.path]).status == 0
        else { return false }
        let designated = run("/usr/bin/codesign", ["-dr", "-", app.path]).output
            .split(separator: "\n").first(where: { $0.hasPrefix("designated") })
        return designated.map(String.init) == "designated => " + requirement.dropFirst()
    }

    /// Chờ SenKey thoát rồi thay app: chép bản mới cạnh bản cũ trước, đổi chỗ sau cùng, lỗi thì mở lại bản cũ.
    private func replaceAndRelaunch(current: URL, with newApp: URL) {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$3.new" "$3.old"
        if ! ditto "$2" "$3.new"; then rm -rf "$3.new"; open "$3"; exit 1; fi
        xattr -dr com.apple.quarantine "$3.new" 2>/dev/null
        mv "$3" "$3.old" && mv "$3.new" "$3" && rm -rf "$3.old"
        [ -d "$3" ] || mv "$3.old" "$3"
        open "$3"
        rm -rf "$4"
        """
        let tmp = newApp.deletingLastPathComponent().deletingLastPathComponent()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script, "senkey-update", String(getpid()), newApp.path, current.path, tmp.path]
        do {
            try p.run()
        } catch {
            alert("Không cập nhật được", error.localizedDescription)
            return
        }
        Log.add("Thoát để cài bản mới")
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
