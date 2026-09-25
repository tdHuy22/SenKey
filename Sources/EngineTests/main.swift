import Foundation


/// Mô phỏng màn hình: áp từng EditResult giống như app thật gửi phím.
func typeWords(_ input: String, method: InputMethod = .telex, modern: Bool = true) -> String {
    let engine = VietnameseEngine(method: method, modernToneStyle: modern)
    var screen: [Character] = []
    for ch in input {
        if ch == "<" { // Backspace
            if !engine.backspace() { engine.reset() }
            if !screen.isEmpty { screen.removeLast() }
            continue
        }
        if let r = engine.process(ch) {
            screen.removeLast(r.backspaces)
            screen.append(contentsOf: r.text)
        } else {
            engine.reset()
            screen.append(ch)
        }
    }
    return String(screen)
}

var failures = 0
var total = 0
func check(_ input: String, _ expected: String, _ method: InputMethod = .telex, modern: Bool = true) {
    total += 1
    let got = typeWords(input, method: method, modern: modern)
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

print("\(total - failures)/\(total) test đạt")
if failures > 0 { exit(1) }

