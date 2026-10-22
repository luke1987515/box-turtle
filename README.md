# box-turtle
# This project just for test.
git link: [https://github.com/luke1987515/box-turtle.git](https://github.com/luke1987515/box-turtle.git)

## 專案說明

AIC/DQA 相關測試腳本與工具集合。最早是 2018 年練習 Git 用的倉庫（當時只有
`IOmeter_bat_tool` 與 `JBOD_LED_Behavior` 兩個子專案），之後陸續把各測試環境
用到的 Batch / Bash / PowerShell / Python / Robot Framework 腳本放了進來。

> 部分目錄內附帶工具本體（`ipmitool.exe`、`sg_*.exe`、cygwin dll、`lxRW_x64`
> 等），僅供自己的測試機使用。

## 結構總覽

（2026-10 整理，約 60 個子目錄、400+ 檔；主要語言：Batch、Robot Framework、
Bash、Python、PowerShell）

### JBOD 機櫃 / 磁碟控制

| 目錄 | 說明 |
|---|---|
| `JBOD_Enable_Disable_Smart_FAN` | Smart FAN 啟用/停用、fan duty 設定 |
| `JBOD_LED_Behavior` | LED 行為測試（4U24、J4078-01 等） |
| `JBOD_ONOFF` | 機櫃開關機（搭配 LCUS-1 relay） |
| `LCUS-1_CH340T_USB_powered_relay` | CH340T USB 供電 relay：driver 資訊、com port 取得 |
| `Set_JBOD_HDD_Power_Off_On_ipmitool` | 用 ipmitool 控制磁碟電源 on/off |
| `disk_led_tool_10_4` | 磁碟 LED 工具（10.4 版） |
| `disk_ctrl_script_PowerShell` | 磁碟 write cache 檢查/設定（ps1） |
| `make_cache_off` / `make_disk_online` | 快速切換 write cache / disk online-offline |
| `相容性測試_bat_檔` | 相容性測試 bat（write caching、156HDD offline/online） |
| `sg_HDD_off` | 用 sg 工具讓 HDD offline |
| `Scsi_Device_Scan` | SCSI 設備掃描 bat |
| `get_system_sd_list_linux` | 系統 SD 清單（linux） |

### AC / DC 上下電循環

| 目錄 | 說明 |
|---|---|
| `JBOD_DUAL_EXP_AC_cycle` | 雙 EXP AC cycle loop（Windows bat，Pri/Sec） |
| `JBOD_DUAL_EXP_AC_cycle_Linux` | 同上，Linux 版 |
| `JBOD_DUAL_EXP_AC_cycle_Linux(GPIOD7)` | GPIOD7 relay 版（附 lxRW_x64） |
| `JBOD_BMC_DC_Cycle_PowerShell_Script` | BMC DC cycle（PowerShell，帶 retry） |
| `loop_AC_get_sel_elist_win` | AC loop + SEL/elist 擷取（CH340T relay，Windows） |
| `zv2_temp_ac_cycle_loop_Linux_Bash` | ZV2 溫度保護 AC cycle loop（BMC SEL mark 方案） |
| `OS_rebooter_script` | OS 重啟腳本（含 HDD 數量檢查） |
| `___rc_count_Script` | AIC_start.sh rc count 腳本 |

### RVI / 儲存壓力測試

| 目錄 | 說明 |
|---|---|
| `EBOD_RVI` | EBOD FIO RVI linux 腳本 |
| `get_RVI_icf_auto` | 擷取 RVI icf（bat） |
| `run_RVI_icf_auto` | 自動執行 RVI icf（bat，多版本） |
| `fio_script` | fio 腳本（bat/sh 雙版本） |
| `fio 半自動2.0` | fio 半自動工具 2.0（cfg/sh，多國語） |
| `Windos_fio_Stress_HDD_PowerShell` | Windows HDD fio 壓力測試（ps1） |
| `IOmeter_bat_tool` | IOmeter 自動執行 bat 工具 |
| `generate_dd_file` | dd 檔案產生 + HDD wipe（`dd_Disk.sh`、`hdd_status.sh`） |

### BMC / IPMI / 偵測

| 目錄 | 說明 |
|---|---|
| `get_IPMI_SDR_info` | 擷取 IPMI SDR（bat） |
| `loop_ipmi_sdr` | 循環讀 IPMI SDR（bat） |
| `ipmi_sdr_analysis` | SDR 分析腳本 |
| `set_bmc_time` / `compare_bmc_time` | BMC 時間設定 / 比對 |
| `sol_screen_all_EXP` | SOL 截圖（all EXP） |
| `minicom_get_exp_info` | minicom 抓 EXP 資訊 |
| `get_EXP_console` / `_linux` / `_with_check_counters_linux` | EXP console 擷取（Windows/Linux，含 counter 檢查版） |
| `Read_E1S_Temp` | 讀 E1S 溫度 |
| `127_BMC_data_reading_for_30_times` | BMC 讀值 30 次（根目錄單檔） |
| `bash_menu_list_example` / `linux_bash_menu_list_example` | bash 選單示例（內含 ipmitool/sg 工具、BMC 密碼/時間 bat） |
| `Get-HostInfo` | 主機資訊（ps1） |

### DQA / 測試自動化

| 目錄 | 說明 |
|---|---|
| `robot_dqa` | DQA Robot Framework 測試（Functionality Test、DUT image、環境配置等；最大子專案） |
| `python_word` | 自動產生 Word 測試文件 |
| `python_xlsx_to_pdf_good_to_go` | xlsx → PDF 測試報告（Jinja2） |
| `merge_excel_by_column` | Excel 按欄合併（py） |

### 其他工具 / 學習

| 目錄 | 說明 |
|---|---|
| `Verify-MD5_PowerShell_LinuxBash` | MD5 驗證（ps1 + sh 雙版本） |
| `make_4U60_SE_4U90_SE_tarball_script` | 4U60/4U90 SE tarball 產生腳本 |
| `pdf_reader2` | PDF 讀取（py） |
| `system_info_checker` | 系統資訊檢查（py） |
| `simple_tkinter_gui` | Tkinter GUI 練習（py） |
| `J2026-01-G5` | J2026 NVMe 資訊擷取（sh） |
| `run_vastdata` | vastdata 相關 |
| `print_time` | 顯示時間（sh） |
| `luke8` / `luke9` | WebAssembly helloworld 練習 |
| `Ofun(樂趣優先)` | 「樂趣優先」文件 |
| `新增資料夾` | 抽獎 bat |
| `sphinx` | Sphinx 文件練習 |

## 環境說明

腳本對應的測試環境不固定（Windows Server + CentOS 機台，會隨測試案遷移）。
目錄名保留當時的命名；**腳本內的 IP / BMC 位址可能是舊的，使用前請先確認**。
