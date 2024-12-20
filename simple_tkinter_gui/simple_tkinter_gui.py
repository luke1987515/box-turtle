import tkinter as tk
from tkinter import ttk

# 建立主視窗
window = tk.Tk()
window.title("多語言 Tkinter 範例")
window.geometry("400x300")  # 設定視窗大小

# 預設語言
current_language = "中文"

# 建立 Notebook (頁簽容器)
notebook = ttk.Notebook(window)

# 建立三個頁簽
tab_main = ttk.Frame(notebook)  # 主頁
tab_language = ttk.Frame(notebook)  # 語言頁簽
tab_about = ttk.Frame(notebook)  # 關於頁簽

# 頁簽標題的初始文字
tab_titles = {
    "中文": ["主頁", "語言", "關於"],
    "English": ["Home", "Language", "About"],
}

# 將頁簽加入 Notebook
notebook.add(tab_main, text=tab_titles["中文"][0])  # 預設「主頁」
notebook.add(tab_language, text=tab_titles["中文"][1])  # 預設「語言」
notebook.add(tab_about, text=tab_titles["中文"][2])  # 預設「關於」
notebook.pack(expand=True, fill="both")  # 自動擴展和填滿

# -----------------------
# 主頁內容
# -----------------------
main_label = tk.Label(tab_main, text="歡迎使用這個程式!", font=("Arial", 12))
main_label.pack(pady=20)

def on_button_click():
    """按鈕點擊事件處理"""
    if current_language == "中文":
        main_label.config(text="按鈕被按下了!")
    elif current_language == "English":
        main_label.config(text="Button clicked!")

main_button = tk.Button(tab_main, text="按我", command=on_button_click, font=("Arial", 12))
main_button.pack(pady=10)

def update_main_tab():
    """根據語言更新主頁內容"""
    if current_language == "中文":
        main_label.config(text="歡迎使用這個程式!")
        main_button.config(text="按我")
    elif current_language == "English":
        main_label.config(text="Welcome to this program!")
        main_button.config(text="Click Me")

# -----------------------
# 語言頁簽內容
# -----------------------
language_label = tk.Label(tab_language, text="選擇語言 / Select Language:", font=("Arial", 12))
language_label.pack(pady=10)

def on_language_change(event):
    """當語言變更時更新所有頁簽與內容"""
    global current_language
    current_language = language_var.get()
    update_tab_titles()
    update_main_tab()
    update_about_tab()

# 語言選擇下拉選單
language_var = tk.StringVar(value=current_language)
language_dropdown = ttk.Combobox(tab_language, textvariable=language_var, state="readonly",
                                 values=["中文", "English"], font=("Arial", 12))
language_dropdown.pack(pady=10)
language_dropdown.bind("<<ComboboxSelected>>", on_language_change)

# -----------------------
# 關於頁簽內容
# -----------------------
about_label = tk.Label(tab_about, text="這是一個多語言範例程式。", font=("Arial", 12))
about_label.pack(pady=20)

def update_about_tab():
    """根據語言更新關於內容"""
    if current_language == "中文":
        about_label.config(text="這是一個多語言範例程式。")
    elif current_language == "English":
        about_label.config(text="This is a multi-language example program.")

# -----------------------
# 動態更新頁簽標題
# -----------------------
def update_tab_titles():
    """根據語言更新頁簽標題"""
    titles = tab_titles[current_language]
    notebook.tab(0, text=titles[0])  # 更新「主頁」標題
    notebook.tab(1, text=titles[1])  # 更新「語言」標題
    notebook.tab(2, text=titles[2])  # 更新「關於」標題

# -----------------------
# 初始化
# -----------------------
update_main_tab()
update_about_tab()
update_tab_titles()

# 啟動主事件迴圈
window.mainloop()
