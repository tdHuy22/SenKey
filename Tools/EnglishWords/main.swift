// Gõ thử từng từ tiếng Anh bằng Telex (cả kiểu dấu mới và cũ), in ra những từ bị engine đổi.
// Dùng bởi generate.sh.
import Foundation
let words = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).split(separator: "\n")
func type(_ w: String, modern: Bool) -> String {
    let e = VietnameseEngine(method: .telex, modernToneStyle: modern)
    var screen: [Character] = []
    for ch in w + " " {
        if let r = e.process(ch) { screen.removeLast(r.backspaces); screen.append(contentsOf: r.text) }
        else { if let r = e.finishWord() { screen.removeLast(r.backspaces); screen.append(contentsOf: r.text) }; screen.append(ch) }
    }
    return String(screen.dropLast())
}
for w in words {
    let m = type(String(w), modern: true), o = type(String(w), modern: false)
    if m != String(w) || o != String(w) { print("\(w)\t\(m)\t\(o)") }
}
