import os
import glob
import pandas as pd

# 設定目錄路徑
folder_path = "./xlsx_files"  # Excel 檔案所在資料夾
output_file = "merged.xlsx"  # 合併後的輸出檔案

# 指定用來合併的欄位名稱
merge_column = "PartNumber"  # 這裡換成你的主要合併欄位名稱

# 確保資料夾存在
if not os.path.exists(folder_path):
    print(f"❌ 目錄 '{folder_path}' 不存在，請確認路徑是否正確！")
    exit()

# 取得所有 Excel 檔案 (.xls 和 .xlsx)，包括子資料夾內的檔案
xls_files = glob.glob(os.path.join(folder_path, "**", "*.xls"), recursive=True)
xlsx_files = glob.glob(os.path.join(folder_path, "**", "*.xlsx"), recursive=True)

# 轉換 .xls 至 .xlsx
converted_files = []
for xls_file in xls_files:
    try:
        df = pd.read_excel(xls_file, engine="xlrd")
        new_xlsx_file = xls_file + "x"  # 轉換成 .xlsx 副檔名
        df.to_excel(new_xlsx_file, index=False, engine="openpyxl")
        converted_files.append(new_xlsx_file)
        print(f"🔄 已轉換 {xls_file} ➝ {new_xlsx_file}")
    except Exception as e:
        print(f"⚠️ 無法轉換 {xls_file}: {e}")

# 更新文件列表，僅處理 .xlsx 檔案
file_list = xlsx_files + converted_files

if not file_list:
    print("❌ 沒有找到任何 Excel 檔案！")
    exit()

# 初始化 DataFrame 列表
df_list = []

for file_path in file_list:
    file_name = os.path.basename(file_path)  # 取得檔名
    print(f"🔄 正在處理: {file_name}...")

    try:
        df = pd.read_excel(file_path, engine="openpyxl")
    except Exception as e:
        print(f"⚠️ 無法讀取 {file_name}: {e}")
        continue

    # 檢查是否包含合併欄位
    if merge_column not in df.columns:
        print(f"⚠️ 檔案 {file_name} 缺少 '{merge_column}' 欄位，跳過！")
        continue

    # 移除全空的欄位
    df = df.dropna(how="all", axis=1)

    # 加入到列表中
    df_list.append(df)

# 合併所有 DataFrame
if df_list:
    merged_df = pd.concat(df_list, ignore_index=True)

    # 按照 PartNumber 進行合併
    merged_df = merged_df.groupby(merge_column, as_index=False).first()

    # 存成 Excel 檔案
    merged_df.to_excel(output_file, index=False, engine="openpyxl")
    print(f"✅ 合併完成！結果已儲存為：{output_file}")
else:
    print("❌ 沒有可用的檔案進行合併！")
