import pandas as pd
import pdfkit
import os
from jinja2 import Template
from datetime import datetime

# 1. 定義符合您 Excel 標題的 HTML 樣板
html_template = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: "Microsoft JhengHei", sans-serif; margin: 0; padding: 20px; color: #333; line-height: 1.5; }
        .page-wrapper { page-break-after: always; border: 1px solid #2c3e50; padding: 30px; margin-bottom: 20px; position: relative; }
        .header { border-bottom: 3px solid #2c3e50; padding-bottom: 10px; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: baseline; }
        .header h1 { color: #2c3e50; margin: 0; font-size: 24px; }
        .meta-info { display: flex; flex-wrap: wrap; background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .meta-item { width: 50%; margin-bottom: 8px; font-size: 14px; }
        .meta-label { font-weight: bold; color: #555; margin-right: 10px; }
        
        table { width: 100%; border-collapse: collapse; margin-top: 10px; table-layout: fixed; }
        th, td { border: 1px solid #bdc3c7; padding: 12px; text-align: left; vertical-align: top; word-wrap: break-word; }
        th { background-color: #ecf0f1; width: 150px; font-weight: bold; color: #2c3e50; }
        
        .section-title { background-color: #2c3e50; color: white; padding: 8px 12px; font-weight: bold; margin-top: 20px; }
        .status-badge { display: inline-block; padding: 8px 20px; border-radius: 4px; font-weight: bold; color: white; font-size: 18px; }
        .pass { background-color: #27ae60; }
        .fail { background-color: #c0392b; }
        .footer { margin-top: 40px; font-size: 11px; color: #95a5a6; text-align: center; border-top: 1px solid #eee; padding-top: 10px; }
    </style>
</head>
<body>
    {% for row in data %}
    <div class="page-wrapper">
        <div class="header">
            <h1>TEST CASE REPORT</h1>
            <span style="font-size: 14px;">Case No: <strong>{{ row.get('No', 'N/A') }}</strong></span>
        </div>
        
        <div class="meta-info">
            <div class="meta-item"><span class="meta-label">Section:</span>{{ row.get('Section', '-') }}</div>
            <div class="meta-item"><span class="meta-label">Category:</span>{{ row.get('Test Categorization', '-') }}</div>
            <div class="meta-item" style="width: 100%;"><span class="meta-label">Subject:</span><strong>{{ row.get('Test Subject', '-') }}</strong></div>
        </div>

        <div class="section-title">Description</div>
        <p style="padding: 0 10px;">{{ row.get('Description', '-') }}</p>

        <table>
            <tr>
                <th>Test Procedures</th>
                <td>{{ (row.get('Test Procedures', '') | string).replace('\\n', '<br>') | safe }}</td>
            </tr>
            <tr>
                <th>Pass Criteria</th>
                <td>{{ (row.get('Pass Criteria', '') | string).replace('\\n', '<br>') | safe }}</td>
            </tr>
            <tr>
                <th>Test Result</th>
                <td>{{ row.get('Test Result', '-') }}</td>
            </tr>
        </table>

        <div style="margin-top: 30px; text-align: right;">
            <span class="status-badge {{ 'pass' if 'pass' in (row.get('Test Result', '')|string)|lower|trim else 'fail' }}">
                RESULT: {{ row.get('Test Result', 'N/A') }}
            </span>
        </div>
        
        <div class="footer">
            Generated on {{ current_date }} | Internal Document
        </div>
    </div>
    {% endfor %}
</body>
</html>
"""

def excel_to_professional_pdf(folder_path):
    path_wkhtmltopdf = r'C:\Program Files\wkhtmltopdf\bin\wkhtmltopdf.exe'
    config = pdfkit.configuration(wkhtmltopdf=path_wkhtmltopdf)
    
    options = {
        'encoding': "UTF-8",
        'page-size': 'A4',
        'margin-top': '0.4in',
        'margin-right': '0.4in',
        'margin-bottom': '0.4in',
        'margin-left': '0.4in',
        'quiet': ''
    }

    template = Template(html_template)
    files = [f for f in os.listdir(folder_path) if f.endswith(".xlsx") and not f.startswith("~$")]

    current_date = datetime.now().strftime("%Y-%m-%d")

    for file_name in files:
        full_path = os.path.join(folder_path, file_name)
        try:
            # 讀取 Excel 並處理空值
            df = pd.read_excel(full_path).fillna('')
            data_list = df.to_dict(orient='records')
            
            # 渲染 HTML 內容
            rendered_html = template.render(data=data_list, current_date=current_date)
            
            # 輸出檔名增加 _Report 後綴
            output_pdf = os.path.join(folder_path, file_name.replace(".xlsx", "_Report.pdf"))
            pdfkit.from_string(rendered_html, output_pdf, configuration=config, options=options)
            print(f"✅ 已完成: {file_name} -> {os.path.basename(output_pdf)}")
            
        except Exception as e:
            print(f"❌ 錯誤 {file_name}: {e}")

if __name__ == "__main__":
    folder = r'C:\Users\Administrator\Downloads\python_xlsx_to_pdf'
    excel_to_professional_pdf(folder)