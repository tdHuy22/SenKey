import AppKit

// KeyProbe: ghi lại mọi sự kiện phím mà ô chữ nhận được, để chẩn đoán GoViet.
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let input = NSTextView()
    let log = NSTextView()
    var lines: [String] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "KeyProbe – gõ thử vào ô trên"
        let split = NSSplitView(frame: window.contentView!.bounds)
        split.autoresizingMask = [.width, .height]
        for (tv, font) in [(input, NSFont.systemFont(ofSize: 22)), (log, NSFont.monospacedSystemFont(ofSize: 11, weight: .regular))] {
            let sv = NSScrollView()
            sv.hasVerticalScroller = true
            tv.font = font
            tv.isRichText = false
            tv.autoresizingMask = [.width]
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticSpellingCorrectionEnabled = false
            sv.documentView = tv
            split.addSubview(sv)
        }
        log.isEditable = false
        split.isVertical = false
        window.contentView = split
        split.setPosition(140, ofDividerAt: 0)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(input)
        NSApp.activate(ignoringOtherApps: true)

        let t0 = ProcessInfo.processInfo.systemUptime
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self else { return e }
            let cg = e.cgEvent
            let src = cg?.getIntegerValueField(.eventSourceStateID) ?? 0
            let user = cg?.getIntegerValueField(.eventSourceUserData) ?? 0
            let chars = (e.characters ?? "").unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
            let line = String(format: "%7.3f %@ key=%3d chars=%@ %@ flags=0x%llx repeat=%d src=%lld synth=%@",
                              e.timestamp - t0, e.type == .keyDown ? "DOWN" : "up  ", e.keyCode,
                              "\"\(e.characters ?? "")\"", chars, UInt64(e.modifierFlags.rawValue),
                              e.isARepeat ? 1 : 0, src, user != 0 ? "GoViet" : "-")
            self.append(line)
            DispatchQueue.main.async { self.append("        → ô chữ: \"\(self.input.string)\"") }
            return e
        }
        let clear = NSMenuItem(title: "Xoá", action: #selector(clearAll), keyEquivalent: "k")
        clear.target = self
        let appMenu = NSMenu()
        appMenu.addItem(clear)
        appMenu.addItem(NSMenuItem(title: "Copy log", action: #selector(copyLog), keyEquivalent: "l"))
        appMenu.items.last?.target = self
        appMenu.addItem(NSMenuItem(title: "Thoát", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let bar = NSMenu()
        let root = NSMenuItem()
        root.submenu = appMenu
        bar.addItem(root)
        NSApp.mainMenu = bar
        append("Gõ \"maf\" vào ô phía trên. ⌘L để copy log, ⌘K để xoá.")
    }

    func append(_ s: String) {
        lines.append(s)
        log.string = lines.joined(separator: "\n")
        log.scrollToEndOfDocument(nil)
        try? log.string.write(toFile: NSHomeDirectory() + "/Desktop/KeyProbe.log", atomically: true, encoding: .utf8)
    }
    @objc func clearAll() { lines = []; input.string = ""; append("(đã xoá)") }
    @objc func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log.string, forType: .string)
    }
}

let app = NSApplication.shared
let d = Delegate()
app.delegate = d
app.setActivationPolicy(.regular)
app.run()
