# docx_rebuild_ooxml (2026-11)

`python_word` 之前那組（python-docx 對象模型）的結果是「失敗」：
json 化不了圖片、頁首、頁尾。這組換思路：不經過 python-docx，
直接讀寫 docx 裡面的 OOXML（`word/document.xml`），
走「解析 → 結構化內容模型 (JSON) → 用程式重新組裝 docx」。

做法重點：
* 解析時保留每個格式片段（pPr / rPr / tblPr / tcPr…）的原生 XML，
  隱藏元素（bookmark、proofErr）刻意丟棄
* 重新組裝時 100% 由程式從 JSON 模型生成 `word/document.xml`；
  styles / theme / numbering / media / header / footer 從原始包
  原樣複用（等同套用同一份模板）
* 驗證：複雜報告（10 張表格、420 列、3 張圖片、欄位、超連結）
  文字節點全同、結構 11 項全對齊、zip 28 個部分中 27 個位元組一致
* 位元組完全一致不可能（zip 時間戳、XML 排版），
  目標是「內容＋版式級一致」

檔案：
* `parser.py`    original.docx → content.json
* `generate.py`  content.json ＋ 原始包 → rebuilt.docx
* `compare.py`   兩份 docx 的文字 / 結構 / zip 部分比對

執行（Windows/Linux 皆可）：
```
pip install lxml python-docx
python parser.py   original.docx
python generate.py original.docx rebuilt.docx
python compare.py  original.docx rebuilt.docx
```

注意：實驗用的原始檔不放在本 repo（內部文件不公開），
只放通用工具本體。
