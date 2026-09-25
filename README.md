<div align="center">

# 🇻🇳 SenKey

**Bộ gõ tiếng Việt cho macOS: nhẹ, ổn định, không lặp chữ**

Telex · VNI · kiểu gõ riêng cho từng ứng dụng · không gạch chân (marked text)

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![Swift 5](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
![Universal](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-4B8BBE)
![Tests](https://img.shields.io/badge/tests-77%2F77%20passing-2ea44f)
![Speed](https://img.shields.io/badge/engine-~1.2%C2%B5s%2Fph%C3%ADm-orange)

[Cài đặt](#-cài-đặt) · [Sử dụng](#-sử-dụng) · [Cách hoạt động](#-vì-sao-ổn-định-hơn) · [Gỡ cài đặt](#-gỡ-cài-đặt) · [Donate](#-nạp-token-cho-tác-giả)

</div>

---

## ✨ Tính năng

|  |  |
|---|---|
| ⌨️ **Telex & VNI** | Đặt dấu kiểu mới (`hoà`) hoặc kiểu cũ (`hòa`), kiểm tra âm tiết hợp lệ |
| 🎯 **Riêng cho từng app** | VS Code gõ tiếng Anh, Messenger gõ Telex, Excel gõ VNI. SenKey tự nhớ |
| 🚫 **Không marked text** | Không có chữ gạch chân, không lặp chữ kiểu `viêviệt` |
| 🌐 **Sửa lỗi ô gợi ý** | Thanh địa chỉ Chrome / Safari / Firefox / Edge / Arc / Cốc Cốc, Spotlight, Raycast, Alfred, Excel |
| 🔤 **Tự khôi phục tiếng Anh** | `windows`, `google`, `facebook` vẫn là chính nó |
| ⚡ **Siêu nhẹ** | Engine xử lý mỗi phím trong khoảng 1,2 µs, app nằm gọn trên menu bar |
| 🛡️ **An toàn** | Tự gỡ bộ bắt phím trong 0,5 giây khi mất quyền Trợ năng, không làm treo máy |

## 📦 Cài đặt

### Cách 1: Tải bản cài sẵn

1. Tải `SenKey-x.y.zip` ở trang [**Releases**](https://github.com/tdHuy22/SenKey/releases/latest), giải nén rồi kéo `SenKey.app` vào **Applications**.
2. SenKey chưa được Apple công chứng (notarize), nên lần đầu mở macOS sẽ chặn. Chọn **một** trong hai cách:
   - Mở SenKey, bấm **Xong**, rồi vào Cài đặt hệ thống → **Quyền riêng tư & Bảo mật**, kéo xuống dưới và bấm **Vẫn mở** (*Open Anyway*).
   - Hoặc chạy lệnh:
     ```bash
     xattr -dr com.apple.quarantine /Applications/SenKey.app
     ```

### Cách 2: Build từ mã nguồn

Chỉ cần Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/tdHuy22/SenKey.git
cd SenKey
./make-cert.sh   # chỉ cần chạy một lần (khuyên dùng, xem bên dưới)
./install.sh     # build, chép vào /Applications, mở app
```

### Sau khi cài

1. **Cấp quyền:** Cài đặt hệ thống → Quyền riêng tư & Bảo mật → **Trợ năng** → bật **SenKey**.
2. **Tắt bộ gõ khác:** Bàn phím → Nguồn đầu vào → chỉ để lại **ABC**, để không bị xử lý hai lần.
3. Thấy chữ **Vi** trên menu bar là xong. 🎉

Cập nhật: tải bản mới ở Releases, hoặc chạy lại `./install.sh` nếu build từ mã nguồn.

> [!WARNING]
> **Không bật/tắt quyền Trợ năng của SenKey khi app đang chạy.** Trên một số bản macOS, thu hồi quyền của một app
> đang chặn phím có thể làm treo bàn phím và chuột. Hãy **Thoát SenKey** trước, hoặc chỉ dùng `./install.sh`
> (script tự thoát app và xoá quyền cũ).

<details>
<summary><b>🔏 Vì sao nên chạy <code>make-cert.sh</code>?</b></summary>

<br>

Script tạo chứng chỉ tự ký **"SenKey Dev"** trong một keychain riêng tại
`~/Library/Application Support/SenKey/signing/`. Nó không đụng vào keychain đăng nhập và không hỏi mật khẩu máy.

`build.sh` tự dùng chứng chỉ này, nên mọi bản build có **cùng chữ ký**. Nhờ vậy khi cập nhật bằng `./install.sh`,
macOS vẫn nhận ra đó là cùng một app và bạn **không phải cấp lại quyền Trợ năng**.

Nếu không có chứng chỉ, app được ký ad-hoc và mỗi lần cài phải cấp lại quyền.

</details>

## 🚀 Sử dụng

| Thao tác | Kết quả |
|---|---|
| Nhìn biểu tượng **Vi / En** trên menu bar | Trạng thái của ứng dụng đang dùng |
| Nhấn rồi thả **⌃⇧** (Control + Shift) | Đảo Việt/Anh cho *riêng app hiện tại*, app tự ghi nhớ |
| Menu → **Kiểu gõ cho ‹app›** | Theo mặc định · Telex · VNI · Tiếng Anh |
| Menu → **Cài đặt & danh sách ứng dụng…** | Xem, sửa, xoá cài đặt của từng app |

Phím tắt có thể đổi sang **⌥Z**, **⌃Space** hoặc **⌘⇧Space** trong Cài đặt.

## 🧠 Vì sao ổn định hơn

```mermaid
flowchart LR
    A[Phím bấm] --> B[CGEventTap]
    B --> C{VietEngine}
    C -- không đổi gì --> D[Giữ nguyên phím gốc]
    C -- có thay đổi --> E[Gửi phần chênh lệch<br/>⌫ ⌫ + ệt]
```

- **Không dùng marked text.** Mỗi phím chỉ gửi phần chênh lệch: `viet` + `j` → xoá 2 ký tự, gõ `ệt`.
  Nếu phím không làm thay đổi gì, phím gốc được giữ nguyên.
- **Ô gợi ý được xử lý riêng.** SenKey gõ trước một ký tự vô hình để huỷ phần gợi ý đang bôi đen rồi mới xoá.
  Bật/tắt được cho từng app.
- **Nhận đúng app đang nhận phím** qua Accessibility. Spotlight và Raycast không phải app ở phía trước, nhưng vẫn được nhận đúng.
- **Không sửa nhầm chỗ khác.** Từ đang gõ bị bỏ khi bạn click chuột, đổi app hoặc dùng ⌘ / ⌃ / ⌥.
- **Tự hồi phục.** Nếu macOS tắt event tap khi hệ thống quá tải, SenKey tự bật lại.

## ⚠️ Giới hạn

- Ô mật khẩu và **Secure Keyboard Entry** (Terminal, 1Password…) chặn mọi bộ gõ dạng này, nên gõ ra chữ không dấu.
- Sau khi nhấn Space rồi Backspace quay lại từ trước, cần gõ lại cả từ để thêm dấu.

## 🗑️ Gỡ cài đặt

```bash
./uninstall.sh
```

Script thoát app, xoá `/Applications/SenKey.app`, xoá quyền Trợ năng và cài đặt đã lưu. Thư mục mã nguồn được giữ nguyên.
Nếu đã bật *Khởi động cùng macOS*, kiểm tra thêm **Cài đặt chung → Mục đăng nhập**.

## 🏗️ Cấu trúc dự án

```
SenKey/
├── Sources/
│   ├── VietEngine/VietnameseEngine.swift   # Telex/VNI, vị trí dấu, kiểm tra hợp lệ, backspace
│   ├── SenKey/
│   │   ├── KeyboardHook.swift              # CGEventTap, gửi Backspace + Unicode, phím tắt
│   │   ├── Settings.swift                  # cài đặt theo ứng dụng (UserDefaults)
│   │   ├── AppDelegate.swift               # menu bar
│   │   └── SettingsView.swift              # cửa sổ cài đặt (SwiftUI)
│   └── EngineTests/main.swift              # 77 test mô phỏng gõ, chạy tự động khi build
├── Tools/KeyProbe/                         # công cụ ghi log sự kiện phím để debug
├── build.sh · install.sh · uninstall.sh · make-cert.sh
```

Build thủ công: `./build.sh` (dùng `swiftc` trực tiếp, không cần Xcode project hay SwiftPM). Build xong sẽ có file `build/SenKey.app` dạng universal (arm64 + x86_64).

---

## ☕ Nạp token cho tác giả

SenKey **miễn phí**. Nhưng code này được viết cùng một con AI, và con AI đó **ăn token như uống nước** 🥲

Mỗi lần sửa bug lặp chữ, nó đọc lại `KeyboardHook.swift` từ đầu, suy nghĩ ba trang giấy rồi mới kết luận:
*"À, lỗi do keycode 0"*. Nếu SenKey giúp bạn bớt gõ `viêviệt`, hãy cân nhắc nạp chút năng lượng:

| Gói | Giá | Bạn nhận được |
|---|---|---|
| 🍵 **Trà đá** | [5.000đ](https://img.vietqr.io/image/BIDV-7110435358-qr_only.png?addInfo=Donate%20SenKey&amount=5000) | AI đọc được đúng một câu `import AppKit` |
| ☕ **Cà phê sữa đá** | [20.000đ](https://img.vietqr.io/image/BIDV-7110435358-qr_only.png?addInfo=Donate%20SenKey&amount=20000) | Đủ token để AI xin lỗi *"Bạn nói đúng, tôi đã nhầm"* thêm 3 lần |
| 🍜 **Tô phở** | [50.000đ](https://img.vietqr.io/image/BIDV-7110435358-qr_only.png?addInfo=Donate%20SenKey&amount=50000) | Sửa được một bug. Có thể sinh thêm một bug khác, miễn phí |
| 🧋 **Trà sữa full topping** | [100.000đ](https://img.vietqr.io/image/BIDV-7110435358-qr_only.png?addInfo=Donate%20SenKey&amount=100000) | AI được *thinking* thật sâu thay vì đoán mò |
| 🔋 **Sạc đầy context window** | [500.000đ](https://img.vietqr.io/image/BIDV-7110435358-qr_only.png?addInfo=Donate%20SenKey&amount=500000) | Refactor cả project mà không bị quên đầu quên đuôi |
| 🚀 **Nhà tài trợ kim cương** | [Tuỳ tâm](https://img.vietqr.io/image/BIDV-7110435358-qr_only.png?addInfo=Donate%20SenKey) | Tên bạn được khắc trong một comment `// cảm ơn` ở `VietnameseEngine.swift` |

<div align="center">

<img src="docs/donate-qr.jpg" width="260" alt="Mã VietQR donate">

Quét bằng app ngân hàng bất kỳ (VietQR · Napas 247), MoMo hoặc ZaloPay. Bấm vào **giá** trong bảng để có mã QR điền sẵn số tiền 😉

<sub>Không donate cũng không sao: ⭐ star repo cũng là một dạng token tinh thần.</sub>

</div>

---

<div align="center">
<sub>Làm với ❤️, ☕ và rất nhiều token tại Việt Nam.</sub>
</div>
