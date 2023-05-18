import pdfplumber
import os
import pathlib
import sys

device_module_names = ['ST1200MM0018']

if len(sys.argv) == 1:
    device_module_names = ['ST1200MM0018']
    #print(device_module_names)
else:
    device_module_names = sys.argv[1:]
    #print(device_module_names)

for file in os.listdir(pathlib.Path(__file__).parent.resolve()):
    filename = os.fsdecode(file)
    #print(file)
    if filename.endswith('.pdf'):
        all_text = '' # new line
        with pdfplumber.open(file) as pdf:
            # page = pdf.pages[0] - comment out or remove line
            # text = page.extract_text() - comment out or remove line
            for pdf_page in pdf.pages:
               single_page_text = pdf_page.extract_text()
               #print( single_page_text )
               # separate each page's text with newline
               all_text = all_text + '\n' + single_page_text
            #print(all_text)
            # print(text) - comment out or remove line
            for device_module_name in device_module_names:
                if device_module_name in all_text:
                    #print(device_module_name)
                    print('{} in a file {}'.format(device_module_name, filename))
                else:
                    print('string {} does NOT exist in a file {}'.format(device_module_name, filename))
