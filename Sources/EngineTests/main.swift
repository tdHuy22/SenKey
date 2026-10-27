import Foundation


/// Mô phỏng màn hình: áp từng EditResult giống như app thật gửi phím.
/// "<" là Backspace, "⎋" là Esc, "⌥" là nhấn-thả Option (gõ nguyên phím từ kế tiếp).
func typeWords(_ input: String, method: InputMethod = .telex, modern: Bool = true, restore: Bool = true,
               setup: (VietnameseEngine) -> Void = { _ in }) -> String {
    let engine = VietnameseEngine(method: method, modernToneStyle: modern, autoRestoreEnglish: restore)
    setup(engine)
    var screen: [Character] = []
    func apply(_ r: EditResult) {
        screen.removeLast(r.backspaces)
        screen.append(contentsOf: r.text)
    }
    for ch in input {
        if ch == "<" { // Backspace
            if !engine.backspace() { engine.reset() }
            if !screen.isEmpty { screen.removeLast() }
            continue
        }
        if ch == "⎋" {
            if let r = engine.restoreRaw() { apply(r) } else { engine.reset() }
            continue
        }
        if ch == "⌥" {
            if let r = engine.restoreRaw() { apply(r) } else if engine.isEmpty { engine.typeNextWordAsIs = true }
            continue
        }
        if let r = engine.process(ch) {
            screen.removeLast(r.backspaces)
            screen.append(contentsOf: r.text)
        } else {
            // Giống KeyboardHook: phím ngoài từ (Space, dấu câu…) kết thúc từ trước khi đi qua
            if let r = engine.finishWord() {
                screen.removeLast(r.backspaces)
                screen.append(contentsOf: r.text)
            }
            screen.append(ch)
        }
    }
    return String(screen)
}

var failures = 0
var total = 0
func check(_ input: String, _ expected: String, _ method: InputMethod = .telex, modern: Bool = true, restore: Bool = true,
           setup: (VietnameseEngine) -> Void = { _ in }) {
    total += 1
    let got = typeWords(input, method: method, modern: modern, restore: restore, setup: setup)
    if got != expected {
        failures += 1
        print("FAIL [\(method.displayName)] \"\(input)\" → \"\(got)\" (mong đợi \"\(expected)\")")
    }
}

// Telex cơ bản
check("vieetj nam", "việt nam")
check("tieengs Vieetj", "tiếng Việt")
check("nguowif", "người")
check("dduowcj", "được")
check("hoaf", "hoà")
check("hoaf", "hòa", modern: false)
check("hoangf", "hoàng", modern: false)
check("thuyr", "thuỷ")
check("thuyr", "thủy", modern: false)
check("khoer", "khoẻ")
check("quoocs", "quốc")
check("gias", "giá")
check("gif", "gì")
check("giuwax", "giữa")
check("gioongs", "giống")
check("khuyeenr", "khuyển")
check("nguyeenx", "nguyễn")
check("muaf", "mùa")
check("quaf", "quà")
check("chuwa", "chưa")
check("cuar", "của")
check("ruouwj", "rượu")
check("rwowuj", "rượu")
check("thuongw", "thương")
check("tuw", "tư")
check("tuwj", "tự")
check("yeeu", "yêu")
check("khoong", "không")
check("xoawns", "xoắn")
check("tuaans", "tuấn")
check("huyeenf", "huyền")
check("DDAAYS", "ĐẤY")
check("DDaays", "Đấy")
check("Nguowif", "Người")
check("tieesng", "tiếng")   // dấu gõ trước phụ âm cuối
check("vieejt", "việt")
check("tiengse", "tiếng")   // mũ gõ sau cùng
check("hoanf", "hoàn")
check("mieengj", "miệng")
check("w", "ư")
check("ww", "w")
check("aa", "â")
check("aaa", "aa")
check("ass", "as")
check("dd", "đ")
check("ddd", "dd")
check("asz", "a")
// Tiếng Anh tự khôi phục
check("windows", "windows")
check("google", "google")
check("facebook", "facebook")
check("https", "https")
check("email", "email")
check("off", "of")
check("qwen", "qwen")
check("qwerty", "qwerty")
check("swift", "swift")
check("quown", "quơn")
check("quys", "quý")
check("quaanf", "quần")
check("qw", "qw")
// Kết thúc từ: không phải âm tiết tiếng Việt thì trả lại phím gốc
check("user ", "user ")
check("sure.", "sure.")
check("text ", "text ")
check("dduowc ", "đươc ")
check("vieet ", "viêt ")
check("vieetj nam ", "việt nam ")
check("nguowif ", "người ")
check("quoocs ", "quốc ")
check("khuya ", "khuya ")
check("giuwax ", "giữa ")
check("ruouwj ", "rượu ")
check("xooong ", "xoong ")
check("khuyru ", "khuỷu ")
check("nguyeenx ", "nguyễn ")
check("hoachj ", "hoạch ")
check("thuowr ", "thuở ")
// Vần "oeo": "o" sau "oe" là nguyên âm thứ ba, không phải mũ cho "o" đầu
check("khoeof ", "khoèo ")
check("ngoeoj ", "ngoẹo ")
check("ngoejo ", "ngoẹo ")     // dấu gõ trước chữ "o" cuối
check("NGOEOJ ", "NGOẸO ")
check("khoeor ", "khoẻo ")
check("ngoeo5 ", "ngoẹo ", .vni)
check("huow ", "huơ ")
check("thuowng ", "thương ")
check("thuowr ", "thuở ", restore: false)
check("tieengs ", "tiếng ")
check("dd ", "đ ")
check("hoaf ", "hoà ")
check("tex ", "tex ")         // từ điển tiếng Anh
// Từ điển tiếng Anh: chỉ khôi phục khi kết quả không phải từ Việt có thật
check("different ", "different ")
check("possible.", "possible.")
check("Message ", "Message ")
check("more ", "more ")
check("data ", "data ")
check("there ", "thể ")       // "thể" có thật: tiếng Việt thắng
check("this ", "thí ")
check("has ", "há ")
check("has⎋ ", "has ")        // muốn tiếng Anh thì Esc
check("more ", "moẻ ", restore: false)
check("different ", "different ", .vni)  // VNI dùng số làm dấu nên không nuốt chữ
check("tets ", "tét ")
check("dda ", "đa ")
check("quynhf ", "quỳnh ")
check("quyts ", "quýt ")
check("quyeets ", "quyết ")
check("quyx ", "quỹ ")
check("user ", "ủe ", restore: false)
// Backspace
check("vieetj<t", "việt")
check("vieetj<<", "vi")
check("hoafn<", "hoà")
check("nguowif<i", "người")
check("ddaa<aa", "đâ")
check("hoafn<<a", "hoa")
check("tieengs<<<eengs", "tiếng")
check("DDi", "Đi")
// VNI
check("vie65t nam", "việt nam", .vni)
check("d9u7o7c5", "được", .vni)
check("nguo7i2", "người", .vni)
check("hoa2", "hoà", .vni)
check("a11", "a1", .vni)
check("2024", "2024", .vni)
check("tie61ng", "tiếng", .vni)
check("khuye6n3", "khuyển", .vni)
check("xoa8n1", "xoắn", .vni)
// Simple Telex: không có "w" đứng riêng
check("tuw", "tư", .simpleTelex)
check("w", "w", .simpleTelex)
check("nguowif", "người", .simpleTelex)
check("dduowcj", "được", .simpleTelex)
check("wow ", "wow ", .simpleTelex)
// VIQR
check("vie^.t nam", "việt nam", .viqr)
check("ddu+o+.c", "được", .viqr)
check("ngu+o+`i", "người", .viqr)
check("hoa`", "hoà", .viqr)
check("Tie^'ng Vie^.t", "Tiếng Việt", .viqr)
check("a(n", "ăn", .viqr)
check("a''", "a'", .viqr)
check("di. ", "dị ", .viqr)
check("ddi\\. ", "đi. ", .viqr)
check("sao? ", "sảo ", .viqr)
check("ok? ", "ok? ", .viqr)
check("no' ", "nó ", .viqr)
check("x.y", "x.y", .viqr)
// Quick Telex
let quick: (VietnameseEngine) -> Void = { $0.quickTelex = true }
check("ccaf ", "chà ", setup: quick)
check("gga ", "gia ", setup: quick)
check("kkoong ", "không ", setup: quick)
check("nnuwowif ", "người ", setup: quick)
check("qqaf ", "quà ", setup: quick)
check("ppowr ", "phở ", setup: quick)
check("ttuw ", "thư ", setup: quick)
check("Ccaof ", "Chào ", setup: quick)
check("CCAOF ", "CHÀO ", setup: quick)
check("cc ", "cc ", .vni, setup: quick)
check("caf ", "cà ")  // tắt mặc định
// Phụ âm đầu/cuối gõ tắt
let qStart: (VietnameseEngine) -> Void = { $0.quickStartConsonant = true }
check("foos ", "phố ", setup: qStart)
check("jaf ", "già ", setup: qStart)
check("waf ", "quà ", setup: qStart)
check("Foos ", "Phố ", setup: qStart)
let qEnd: (VietnameseEngine) -> Void = { $0.quickEndConsonant = true }
check("ag ", "ang ", setup: qEnd)
check("tihf ", "tình ", setup: qEnd)
check("thiks ", "thích ", setup: qEnd)
check("viek ", "viek ", setup: qEnd)  // "viêch" không phải tiếng Việt
check("thuowg ", "thương ", setup: qEnd)
check("ok ", "ok ", setup: qEnd)
check("anh ", "anh ", setup: qEnd)
// Esc trả lại phím gốc; Option: gõ nguyên phím từ kế tiếp
check("mix⎋ ", "mix ")
check("vieetj⎋ ", "vieetj ")
check("mix⎋s ", "mixs ")
check("viet⎋ ", "viet ")
check("⌥mix tieengs", "mix tiếng")
check("vieetj⌥ ", "vieetj ")

// Gõ tắt
func expect(_ got: String?, _ want: String?, _ label: String) {
    total += 1
    if got != want { failures += 1; print("FAIL [\(label)] → \(got ?? "nil") (mong đợi \(want ?? "nil"))") }
}
let macros = MacroExpander.table([
    Macro(abbreviation: "ko", text: "không"), Macro(abbreviation: "Btw", text: "by the way"),
    Macro(abbreviation: "ngay", text: "hôm nay {date}"), Macro(abbreviation: "", text: "x"),
    Macro(abbreviation: "a b", text: "x"),
])
let noon = Date(timeIntervalSince1970: 1_699_963_200)  // 12:00 UTC 14/11/2023: vẫn ngày 14 ở mọi múi giờ VN, Mỹ, châu Âu
expect(MacroExpander.expand("ko", table: macros), "không", "ko")
expect(MacroExpander.expand("Ko", table: macros), "Không", "Ko")
expect(MacroExpander.expand("KO", table: macros), "KHÔNG", "KO")
expect(MacroExpander.expand("btw", table: macros), "by the way", "btw")
expect(MacroExpander.expand("BTW", table: macros), "BY THE WAY", "BTW")
expect(MacroExpander.expand("kho", table: macros), nil, "kho")
expect(MacroExpander.expand("", table: macros), nil, "rỗng")
expect(String(MacroExpander.expand("ngay", table: macros, now: noon)!.prefix(10)), "hôm nay 14", "{date}")
expect(macros.count == 3 ? "3" : "\(macros.count)", "3", "bỏ mục rỗng, có khoảng trắng")
// Viết hoa đầu câu
func caps(_ s: String) -> String {
    var c = SentenceCapitalizer()
    return String(s.map { ch -> Character in
        if ch.isLetter { return c.takeLetter() ? Character(ch.uppercased()) : ch }
        c.didType(ch); return ch
    })
}
expect(caps("chào. bạn khoẻ? tôi khoẻ! ok"), "chào. Bạn khoẻ? Tôi khoẻ! Ok", "câu")
expect(caps("3.5 triệu. vâng\rdạ"), "3.5 triệu. Vâng\rDạ", "số, Enter")
expect(caps("a.b"), "a.b", "không có Space")
// Phím tắt, phiên bản
let ctrlShift = HotkeySpec(keyCode: nil, modifiers: HotkeySpec.control | HotkeySpec.shift)
expect(ctrlShift.displayName, "⌃⇧", "⌃⇧")
expect(ctrlShift.isValid ? "ok" : "sai", "ok", "⌃⇧ hợp lệ")
expect(HotkeySpec(keyCode: nil, modifiers: HotkeySpec.option).isValid ? "ok" : "sai", "sai", "⌥ đơn lẻ")
let optZ = HotkeySpec(keyCode: 6, modifiers: HotkeySpec.option, keyLabel: "Z")
expect(optZ.displayName, "⌥Z", "⌥Z")
expect(HotkeySpec(keyCode: 0, modifiers: HotkeySpec.shift).isValid ? "ok" : "sai", "sai", "⇧A")
expect(optZ.matches(keyCode: 6, modifiers: HotkeySpec.option | 0x100) ? "ok" : "sai", "ok", "⌥Z khớp")
expect(optZ.matches(keyCode: 6, modifiers: HotkeySpec.option | HotkeySpec.shift) ? "ok" : "sai", "sai", "⌥⇧Z")
expect(AppVersion.isNewer("v1.2.0", than: "1.1.1") ? "ok" : "sai", "ok", "1.2.0 > 1.1.1")
expect(AppVersion.isNewer("v1.1.1", than: "1.1.1") ? "ok" : "sai", "sai", "bằng nhau")
expect(AppVersion.isNewer("1.10", than: "1.9.9") ? "ok" : "sai", "ok", "1.10 > 1.9.9")
expect(typeWordsKeys("vieetj"), "vieetj", "typedKeys")
func typeWordsKeys(_ s: String) -> String { let e = VietnameseEngine(); for ch in s { _ = e.process(ch) }; return e.typedKeys }

print("\(total - failures)/\(total) test đạt")
if failures > 0 { exit(1) }

