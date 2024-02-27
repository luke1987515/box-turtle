# 將 MarkDown 檔，轉成 PDF 檔

## 如何使用

### 清除舊資料

`make clean`

### 產出 html

`make html`

### 產出 pdf

`make latexpdf`

## 安裝環境

### 安裝 Sphinx

https://www.sphinx-doc.org/en/master/usage/installation.html

`sudo apt-get install python3-sphinx`

`sphinx-quickstart --version`

### 設定 中文化

`sudo apt-get install -y latexmk`

`sudo apt-get install -y perl`

`sudo apt install texlive-xetex`

`sudo apt install texlive-*`

https://learn-rst.readthedocs.io/zh-cn/latest/reST-%E6%89%A9%E5%B1%95/latex.html

Add in conf.py

```
latex_engine = "xelatex"
latex_elements = {
    'papersize': 'a4paper',
    'utf8extra': '',
    'inputenc': '',
    'cmappkg': '',
    'fontenc': '',
    'preamble': r'''
        \usepackage{xeCJK}
        \parindent 2em
        \setcounter{tocdepth}{3}
        \renewcommand\familydefault{\ttdefault}
        \renewcommand\CJKfamilydefault{\CJKrmdefault}
    ''',
}
```

### 設定 支援 Markdown 格式

https://www.sphinx-doc.org/en/master/usage/markdown.html

`pip install myst-parser`

Add in conf.py

```
extensions = ['myst_parser']
```

```
source_suffix = {
    '.rst': 'restructuredtext',
    '.txt': 'markdown',
    '.md': 'markdown',
}

```
