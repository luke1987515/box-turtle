import os
import platform

def check_system_info():
    print("作業系統:", platform.system())
    print("系統版本:", platform.version())
    print("處理器:", platform.processor())
    print("當前目錄:", os.getcwd())

def main():
    print("跨平台腳本測試")
    check_system_info()

if __name__ == "__main__":
    main()

