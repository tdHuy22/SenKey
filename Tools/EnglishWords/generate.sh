#!/bin/bash
# Sinh lại Sources/VietEngine/EnglishWords.swift. Cần swiftc và Python có gói wordfreq (pip install wordfreq).
# Chạy lại khi đổi luật gõ trong VietnameseEngine.swift.
set -euo pipefail
cd "$(dirname "$0")/../.."
PY="${PYTHON:-python3}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. 30.000 từ tiếng Anh phổ biến nhất, chỉ chữ cái
"$PY" -c "
from wordfreq import top_n_list
print('\n'.join(w for w in top_n_list('en', 30000) if w.isascii() and w.isalpha() and len(w) >= 2))" > "$TMP/en.txt"

# 2. Gõ thử bằng engine hiện tại, CHƯA dùng từ điển (để biết từ nào bị gõ hỏng)
echo 'enum EnglishWords { static func contains(_ word: String) -> Bool { false } }' > "$TMP/Empty.swift"
swiftc -O -swift-version 5 -o "$TMP/probe" Sources/VietEngine/VietnameseEngine.swift "$TMP/Empty.swift" Tools/EnglishWords/main.swift
"$TMP/probe" "$TMP/en.txt" > "$TMP/changed.tsv"

# 3. Chọn từ và ghi file Swift
"$PY" Tools/EnglishWords/pick.py < "$TMP/changed.tsv" > "$TMP/words.txt"
VERSION="$("$PY" -c 'import importlib.metadata as m; print(m.version("wordfreq"))')"
{
  echo "// File sinh tự động bởi Tools/EnglishWords/generate.sh (wordfreq $VERSION). Đừng sửa tay."
  echo "// $(wc -l < "$TMP/words.txt" | tr -d ' ') từ tiếng Anh mà Telex gõ hỏng; xem luật chọn trong Tools/EnglishWords/pick.py."
  echo ""
  echo "enum EnglishWords {"
  echo "    static func contains(_ word: String) -> Bool { set.contains(word) }"
  echo ""
  echo "    private static let set: Set<String> = Set(\"\"\""
  fold -s -w 110 < <(tr '\n' ' ' < "$TMP/words.txt") | sed 's/^/        /; s/ *$//'
  echo ""
  echo "        \"\"\".split(whereSeparator: { \$0 == \" \" || \$0 == \"\\n\" }).map(String.init))"
  echo "}"
} > Sources/VietEngine/EnglishWords.swift
echo "✓ $(wc -l < "$TMP/words.txt" | tr -d ' ') từ → Sources/VietEngine/EnglishWords.swift"
