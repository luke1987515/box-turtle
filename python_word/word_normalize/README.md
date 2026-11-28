# word_normalize

AIC Word 報告正常化專案：把不依 Word 撰寫慣例的報告（全直接格式、無樣式語義）
轉成符合 OO 標準慣例的 docx，**外觀必須完全一樣**（判定 = effective formatting
100% 相同），之後拆 part 供 AI 獨立產出/修改再合併。

與本專案相關的前置實驗：`../docx_rebuild_ooxml/`（OOXML 重組 parser/generator）。

## 已定案決策（2026-11-28）
1. 慣例 = OO 標準：內建樣式（Heading 1/2/3、Normal、List、Table Grid、
   Header/Footer、Title/Subtitle）為骨幹，放不下的才開自訂樣式。
   樣式「名字」符合慣例、樣式「屬性」= 原檔 effective formatting（看起來一樣）。
2. 執行粒度 = 逐範圍推進：頁首頁尾 → 封面 → 內文（每範圍獨立驗證）。
3. 角色指派 = AI 判斷 + 使用者抽樣確認（格式簇提案表待審）。
4. 目標檔先簡化 = 「骨架版」：縮減實例、保留全部格式語彙（每角色 1–3 行）；
   有意義的偏差（藍字/Pass 等）是語彙本身，不可修掉。

## 檔案
- `build_skeleton.py`：骨架版建置腳本（lxml；砍表列至簇覆蓋、清 TOC 快取留欄位、裁圖片）
- `verify_skeleton.py`：驗證腳本（python-docx 開啟性 / TOC 欄位平衡 / 格式簇覆蓋 diff）

## 目標檔結構重點（2026 DVT 相容性報告版式）
- 2 sections：封面（titlePg、信紙 first-only、有一個永不顯示的死頁尾）+ 內文（無頁首頁尾）
- 內文 = 10 張 top-level 表；最大的一張表同時裝 Revision History、測試期間、
  TOC 欄位（含 18 項快取）與第 1 章全部內容
- Heading 1/2 全在表格首列；TOC `\o "1-3" \h \z \u` 靠它們活
- 1222 段 1175 無 pStyle、1970 runs 1902 直接 rPr → 確認「未按慣例撰寫」
- 骨架版：1222 → 371 段、59 → 50 格式簇、TOC 快取清空（欄位結構保留，Word 可重生成）

## 坑
- TOC `\h` 的第一個 entry 包在 `w:hyperlink` 元素裡（非段落直接 `w:r`）：
  清 TOC 快取要按「段落所有子元素」切（保留到第一個 `fldChar:separate` 為止）
- 改 document.xml 用 lxml（保 nsmap）；ElementTree 會掉 namespace 宣告
- 驗證三件：python-docx 可開啟、TOC cell 的 fldChar begin/end 平衡、簇覆蓋 diff

## 下一步
1. 骨架版長相確認（Word 開啟）
2. 正常化：effective formatting 解析 → 簇→角色提案表 → 審表 →
   新 styles.xml + 重寫 document.xml → TOC 重生成 → 驗證
3. 拆 part（章節表為界）+ merge（rels 合併、r:id 全域重映射）

> 實驗原始檔（內部報告）不放此 repo。
