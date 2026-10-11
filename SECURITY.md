# Bảo mật

SenKey có quyền Trợ năng, tức là đọc và sửa được mọi phím bạn gõ. Vì vậy mọi lỗi bảo mật của SenKey đều được xem là nghiêm trọng.

## Báo lỗi bảo mật

**Đừng mở issue công khai.** Báo riêng qua [Report a vulnerability](https://github.com/tdHuy22/SenKey/security/advisories/new)
(tab **Security** của repo). Ghi rõ phiên bản macOS, phiên bản SenKey và các bước tái hiện.

*English: please report vulnerabilities privately via [Report a vulnerability](https://github.com/tdHuy22/SenKey/security/advisories/new). Do not open a public issue.*

## Phiên bản được hỗ trợ

Chỉ bản mới nhất trên [Releases](https://github.com/tdHuy22/SenKey/releases/latest). Bản vá được phát hành dưới dạng bản mới.

## Kiểm tra bản cài là thật

Mọi bản phát hành đều ký bằng cùng một chứng chỉ. Lệnh cài một dòng (`get.sh`) tự kiểm chữ ký và từ chối cài nếu sai.
Nếu cài từ file DMG, mở file DMG rồi kiểm **trước khi kéo vào Applications** (in ra `SenKey thật` là đúng; đã cài rồi thì thay đường dẫn bằng `/Applications/SenKey.app`):

```bash
codesign --verify --strict --deep -R '=identifier "vn.senkey.app" and certificate leaf = H"e90227565deafdcd07f260406f4934fe32ed72d6"' /Volumes/SenKey/SenKey.app && echo "SenKey thật"
```

## SenKey làm gì với phím bạn gõ

- Chỉ giữ trong bộ nhớ các chữ của từ đang gõ, để đặt dấu; bỏ đi khi bạn gõ dấu cách, click chuột hay đổi ứng dụng.
- Không gửi phím đi đâu (app không có mã kết nối mạng) và không ghi phím ra file.
- Ô mật khẩu thật bật Secure Input: macOS không đưa phím ở đó cho SenKey.
- Lời hỏi mật khẩu trong Terminal (`sudo`, `ssh`) không phải ô mật khẩu thật: hãy chuyển sang **En** trước khi gõ.
