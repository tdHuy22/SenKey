"""Chọn từ tiếng Anh mà SenKey (Telex) gõ hỏng, để khôi phục khi kết thúc từ.

Đầu vào (stdin): từng dòng "phím gõ<TAB>kết quả kiểu dấu mới<TAB>kết quả kiểu dấu cũ" do main.swift in ra.
Giữ một từ khi nó đủ phổ biến trong tiếng Anh (zipf >= 3, khoảng 1 lần mỗi triệu từ) và:
  - kết quả không có dấu, tức engine nuốt chữ do gõ lặp phím dấu (different → diferent), hoặc
  - kết quả không có trong tiếng Việt (more → moẻ, data → dât).
Từ Việt có thật (this → thí, has → há) luôn thắng: Telex chỉ có đúng cách gõ đó, còn tiếng Anh thì Esc.
"""
import sys
from wordfreq import zipf_frequency as z

keep = set()
for line in sys.stdin:
    raw, modern, old = line.rstrip("\n").split("\t")
    if z(raw, "en") < 3.0:
        continue
    if (modern.isascii() and old.isascii()) or max(z(modern, "vi"), z(old, "vi")) == 0:
        keep.add(raw)
print("\n".join(sorted(keep)))
