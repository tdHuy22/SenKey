# GoViet – Bộ gõ tiếng Việt cho macOS

App nhỏ trên menu bar: gõ Telex/VNI, **chọn kiểu gõ riêng cho từng ứng dụng**, không dùng chữ gạch chân
(marked text) nên không bị lỗi lặp chữ như bộ gõ mặc định của macOS.

## Cài đặt
```bash
cd ~/Documents/Claude/GoViet
./install.sh
```
Script sẽ build, chép `GoViet.app` vào `/Applications` rồi mở app. Sau đó:
1. Cấp quyền: **Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng → bật GoViet**.
2. Trong **Bàn phím → Nguồn đầu vào**, chỉ để **ABC** (gỡ bộ gõ Tiếng Việt của Apple để không bị xử lý hai lần).

Cập nhật sau khi sửa code: chạy lại `./install.sh`.

> ⚠️ **Không bật/tắt quyền Trợ năng của GoViet khi app đang chạy.** Trên một số bản macOS, thu hồi quyền của
> một app đang chặn phím có thể làm treo bàn phím/chuột. Hãy *Thoát GoViet* trước, hoặc chỉ dùng `./install.sh`
> (script tự thoát app và xoá quyền cũ). GoViet cũng tự gỡ bộ bắt phím trong vòng 0,5 giây khi phát hiện mất quyền.

### Chứng chỉ ký riêng (khuyên dùng)
```bash
./make-cert.sh   # chỉ chạy một lần
```
Tạo chứng chỉ tự ký "GoViet Dev" trong keychain riêng
`~/Library/Application Support/GoViet/signing/` (không đụng keychain đăng nhập, không hỏi mật khẩu máy).
`build.sh` tự dùng chứng chỉ này → các bản build có cùng chữ ký → **cập nhật bằng `./install.sh` không phải cấp lại quyền Trợ năng**.
Không có chứng chỉ thì app được ký ad-hoc và mỗi lần cài phải cấp lại quyền.

## Gỡ cài đặt
```bash
~/Documents/Claude/GoViet/uninstall.sh
```
Script thoát app, xoá `/Applications/GoViet.app`, xoá quyền Trợ năng và cài đặt đã lưu. Thư mục mã nguồn được giữ nguyên.
Nếu đã bật "Khởi động cùng macOS", kiểm tra thêm **Cài đặt chung → Mục đăng nhập**.

## Sử dụng
- Biểu tượng **Vi / En** trên menu bar là trạng thái của ứng dụng đang dùng.
- **⌃⇧** (nhấn rồi thả Control+Shift): đảo Việt/Anh cho *riêng ứng dụng hiện tại*, app tự ghi nhớ.
  Có thể đổi sang ⌥Z, ⌃Space, ⌘⇧Space trong Cài đặt.
- Menu → *Kiểu gõ cho <app>*: Theo mặc định / Telex / VNI / Tiếng Anh.
- *Cài đặt & danh sách ứng dụng…*: xem, sửa, xoá cài đặt của từng ứng dụng.

## Vì sao ổn định hơn bộ gõ mặc định
- **Không dùng marked text.** Mỗi phím chỉ gửi phần chênh lệch (vd `viet` + `j` → xoá 2 ký tự, gõ `ệt`).
  Nếu phím không làm thay đổi gì, phím gốc được giữ nguyên.
- **Sửa lỗi ô gợi ý** (thanh địa chỉ Chrome/Safari/Firefox/Edge/Arc/Cốc Cốc, Spotlight, Raycast, Alfred, Excel):
  gõ trước một ký tự vô hình để huỷ phần gợi ý đang bôi đen rồi mới xoá, nên không bị kiểu "viêviệt".
  Bật/tắt được cho từng app.
- **Nhận đúng app đang nhận phím** qua Accessibility (Spotlight/Raycast không phải app frontmost).
- Tự bỏ từ đang gõ khi click chuột, đổi app hoặc dùng phím ⌘/⌃/⌥, để không sửa nhầm chữ ở chỗ khác.
- Tự khôi phục từ tiếng Anh: `windows`, `google`, `facebook` không bị biến thành chữ Việt.
- Tự bật lại event tap nếu macOS tắt nó khi hệ thống quá tải.

## Giới hạn
- Ô mật khẩu / Secure Keyboard Entry (Terminal, 1Password…) chặn mọi bộ gõ dạng này, gõ sẽ ra chữ không dấu.
- Sau khi nhấn Space rồi Backspace quay lại từ trước, cần gõ lại cả từ để thêm dấu.

## Cấu trúc
- `Sources/VietEngine/VietnameseEngine.swift` – xử lý âm tiết: Telex/VNI, vị trí dấu, kiểm tra hợp lệ, backspace
- `Sources/GoViet/KeyboardHook.swift` – CGEventTap, gửi Backspace + Unicode, phím tắt
- `Sources/GoViet/Settings.swift` – cài đặt theo ứng dụng (UserDefaults)
- `Sources/GoViet/AppDelegate.swift`, `SettingsView.swift` – menu bar, cửa sổ cài đặt
- `install.sh`, `uninstall.sh` – cài / gỡ cài đặt
- `Sources/EngineTests/main.swift` – 70 test mô phỏng gõ (chạy tự động trong `build.sh`)
