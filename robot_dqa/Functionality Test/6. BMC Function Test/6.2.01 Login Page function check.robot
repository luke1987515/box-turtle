*** Settings ***
Library     OperatingSystem
Library     String
Library     SeleniumLibrary


*** Variables ***
${bmc_login}    -I lanplus -H 192.168.11.11 -U admin -P admin123
${file_name}    file_with_variable
${BROWSER}      Chrome
${URL}          https://192.168.11.11/
${USERNAME}     admin
${PASSWORD}     admin123


*** Test Cases ***
6.2.1 Login Page function check
    [Documentation]    BMC WEB UI Login function check / mis-operation check
    Open Browser    ${URL}    ${BROWSER}    options=add_argument("--ignore-certificate-errors")
    Maximize Browser Window
    sleep    2
    Input Text    userid    ${USERNAME}
    Input Password    password    ${PASSWORD}
    Click Button    btn-login
    Page Should Not Contain    Login Failed
    sleep    5
    Capture Page Screenshot
    Close Window

6.2.1 Login Page function check --- mis-operation
    [Documentation]    BMC WEB UI Login function check / mis-operation check
    Open Browser    ${URL}    ${BROWSER}    options=add_argument("--ignore-certificate-errors")
    Maximize Browser Window
    sleep    2
    Input Text    userid    ${USERNAME}
    Input Password    password    admin123123
    Click Button    btn-login
    sleep    2
    Page Should Contain    Login Failed
    sleep    2
    Capture Page Screenshot
    Close Window

6.2.1 Login Page function check --- Forgot Password function check / mis-operation check
    [Documentation]    Forgot Password function check / mis-operation check
    Open Browser    ${URL}    ${BROWSER}    options=add_argument("--ignore-certificate-errors")
    Maximize Browser Window
    sleep    2
    Input Text    userid    ${USERNAME}
    Input Password    password    admin123123
    Click Button    btn-login
    sleep    2
    Page Should Contain    Login Failed
    sleep    2
    Click Link    forgot-password
    sleep    1
    Handle Alert    action=ACCEPT
    sleep    1   
    Capture Page Screenshot
    Close Window

# *** Variables ***
# ${BROWSER}    Chrome
# ${URL}    https://example.com
# ${USERNAME}    your_username
# ${PASSWORD}    your_password

# *** Test Cases ***
# Login Test
#    Open Browser    ${URL}    ${BROWSER}
#    Input Text    username_field    ${USERNAME}
#    Input Password    password_field    ${PASSWORD}
#    Click Button    login_button
#    Page Should Contain    Welcome, ${USERNAME}
