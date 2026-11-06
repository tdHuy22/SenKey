"""Chọn từ tiếng Anh mà SenKey (Telex) gõ hỏng, để khôi phục khi kết thúc từ.

Đầu vào (stdin): từng dòng "phím gõ<TAB>kết quả kiểu dấu mới<TAB>kết quả kiểu dấu cũ" do main.swift in ra.
Giữ một từ khi nó đủ phổ biến trong tiếng Anh (zipf >= 3, khoảng 1 lần mỗi triệu từ) và:
  - kết quả không có dấu, tức engine nuốt chữ do gõ lặp phím dấu (different → diferent), hoặc
  - kết quả không có trong tiếng Việt (more → moẻ, data → dât).
Từ Việt có thật (this → thí, has → há) luôn thắng: Telex chỉ có đúng cách gõ đó, còn tiếng Anh thì Esc.

Kho tiếng Việt của wordfreq thiếu từ địa phương và từ ít gặp (dô, ém, hén, ẻm đều có tần suất 0),
nên VIET_WINS ghi tay những cách gõ mà tiếng Việt phải thắng. Chỉ thêm khi đó là cách gõ tự nhiên
của một từ Việt người ta thật sự dùng; từ tiếng Anh quá phổ biến (was → ứa, here → hể) thì để nguyên.
"""
import sys
from wordfreq import zipf_frequency as z

# phím gõ → từ Việt mà Telex phải ra
VIET_WINS = {
    # tiếng miền Nam
    "doo": "dô", "ems": "ém", "dems": "dém", "hens": "hén", "erm": "ẻm", "les": "lé",
    # từ ít gặp mà wordfreq không có
    "ef": "è", "ere": "ể", "hops": "hóp", "mums": "múm", "suns": "sún", "lows": "lớ", "quits": "quít",
    "gis": "gí", "reef": "rề", "rees": "rế", "urn": "ủn", "bern": "bẻn",
}

keep = set()
seen = set()
for line in sys.stdin:
    raw, modern, old = line.rstrip("\n").split("\t")
    if raw in VIET_WINS:
        seen.add(raw)
        if VIET_WINS[raw] not in (modern, old):
            sys.exit(f"VIET_WINS lỗi thời: {raw} giờ ra {modern}/{old}, không phải {VIET_WINS[raw]}")
        continue
    if z(raw, "en") < 3.0:
        continue
    if (modern.isascii() and old.isascii()) or max(z(modern, "vi"), z(old, "vi")) == 0:
        keep.add(raw)
missing = {w for w in VIET_WINS if w not in seen and z(w, "en") >= 3.0}
if missing:
    print(f"Cảnh báo: VIET_WINS có từ engine không còn đổi: {sorted(missing)}", file=sys.stderr)
print("\n".join(sorted(keep)))
