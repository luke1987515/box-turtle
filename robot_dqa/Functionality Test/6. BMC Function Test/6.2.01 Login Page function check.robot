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
${EXPECTED_TITLE}    AIC BMC System

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
    [Teardown]    Close Window

6.2.1 Login Page function check --- mis-operation
    [Documentation]    BMC WEB UI Login function check / mis-operation check
    Open Browser    ${URL}    ${BROWSER}    options=add_argument("--ignore-certificate-errors")
    Maximize Browser Window
    sleep    2
    Input Text    userid    ${USERNAME}
    Input Password    password    admin123123
    Click Button    btn-login
    sleep    2
    #Page Should Contain    Login Failed
    sleep    2
    Capture Page Screenshot
    [Teardown]    Close Window

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
    Click Link    id=forgot-password
    sleep    1
    Handle Alert    action=ACCEPT
    sleep    1   
    Capture Page Screenshot
    [Teardown]    Close Window

# 確認可以 Login 到 UBL 的位置
6.2.XXX [option] Check page 
    Open Browser To Skeep SSL 認證
	[Teardown]    Close Browser

# 此測試是確認網頁的 Title 是 "AIC BMC System"
6.2.XXX [option] Check Page Title
    Open Browser To Skeep SSL 認證
	Maximize Browser Window
	sleep   3s
	Capture Page Screenshot
	${actual_title}=    Get Title
	Should Be Equal As Strings    ${actual_title}    ${EXPECTED_TITLE}
	Title Should Be    ${EXPECTED_TITLE}
    [Teardown]    Close Browser

*** Keywords ***
# 當使用 Robot Framework 開啟網頁會遇到 SSL 認證問題
Open Browser To Skeep SSL 認證
	Open Browser    ${URL}    ${BROWSER}
	Click Button    details-button
	Click Element   xpath://a[@id='proceed-link']



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
