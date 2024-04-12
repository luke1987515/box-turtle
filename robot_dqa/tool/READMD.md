
# Install Chocolatey
```
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```
# Install python
```
choco install python
```
```
choco install git
```
```
choco install vscode
```
# pip upgrade pip
```
python -m pip install --upgrade pip
```
# pip upgrade all
```
pip freeze | %{$_.split('==')[0]} | %{pip install --upgrade $_}
```

# Install 
```
pip install robotframework
```
```
pip install robotframework-seleniumlibrary
```
```
pip install selenium
```
```
pip install rpa
```
