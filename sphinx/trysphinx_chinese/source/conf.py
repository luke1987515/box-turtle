# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#project-information

project = 'Try Sphinx'
copyright = '2024, Luke'
author = 'Luke'

# -- General configuration ---------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#general-configuration

extensions = []

templates_path = ['_templates']
exclude_patterns = []



# -- Options for HTML output -------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#options-for-html-output

html_theme = 'alabaster'
html_static_path = ['_static']

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
