*** Settings ***
Library     SeleniumLibrary


*** Test Cases ***
Open Google
    Open Browser    https://www.google.com    chrome
    sleep    1
    Capture Page Screenshot


Open 192.168.11.11 --- Chrome ssl
    Open Browser    https://192.168.11.11/    chrome
    sleep    2
    Capture Page Screenshot


Open 192.168.11.11 --- Firefox ssl
    Open Browser    https://192.168.11.11/    firefox
    sleep    2
    Capture Page Screenshot



Open 192.168.11.11 --- Chrome
    Open Browser    https://192.168.11.11/    chrome    options=add_argument("--ignore-certificate-errors")
    sleep    2
    Capture Page Screenshot


Open 192.168.11.11 --- Firefox
    Open Browser    https://192.168.11.11/    firefox    options=add_argument("--ignore-certificate-errors")
    sleep    2
    Capture Page Screenshot

    [Teardown]    Close All Browsers
