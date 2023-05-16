*** Settings ***
Library     OperatingSystem
Library     String
Library     SeleniumLibrary


*** Variables ***
${bmc_login}    -I lanplus -H 192.168.11.11 -U admin -P admin123
${file_name}    file_with_variable


*** Test Cases ***
# Test Case sel clear
#    Set Suite Variable    ${file_name}    BMC_sel_clear
#    ${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe ${bmc_login} sel clear
#    sleep    3
#    #${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 fru
#    ${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe ${bmc_login} sel list
#    Log to console    ${\n}
#    Log to console    ${result}
#    Create File    ${EXECDIR}/${file_name}.txt    ${result}
#    #${frt}    Run    type ${file_name}.txt | find "Product Name"
#    #Log To Console    [${frt}]
#    #${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
#    #Log To Console    [${Product_Name}]

#    Should Be Equal As Strings    SEL has no entries    ${result}

Perform Hot-swap the power module and power cord ten times, and verify the functions be listed on right side. 1
    [Documentation]    Hot-swap PSU under 'power on' state, check fail LED, beeper, and console status that can work properly.
    Set Suite Variable    ${file_name}    EXP_console_sensor
    #${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 fru
    ${result}    Run    del /S EXP_console_sensor.txt
    ${result}    Run
    ...    ${EXECDIR}/tool/teraterm-4.106/ttermpro.exe /I /C=3 /BAUD=38400 /L=${EXECDIR}/${file_name}.txt /M=${EXECDIR}/tool/teraterm-4.106/script/exp_sensor.ttl
    Log to console    ${\n}
    Log to console    ${result}
    #Create File    ${EXECDIR}/${file_name}.txt    ${result}

Perform Hot-swap the power module and power cord ten times, and verify the functions be listed on right side. 2
    [Documentation]    Hot-swap PSU under 'power on' state, check fail LED, beeper, and console status that can work properly.
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "PSU1 Status"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    Ok    ${Product_Name}

Perform Hot-swap the power module and power cord ten times, and verify the functions be listed on right side. 3
    [Documentation]    Hot-swap PSU under 'power on' state, check fail LED, beeper, and console status that can work properly.
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "PSU2 Status"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    Ok    ${Product_Name}

Perform Hot-swap the power module and power cord ten times, and verify the functions be listed on right side. 4
    [Documentation]    Hot-swap PSU under 'power on' state, check fail LED, beeper, and console status that can work properly.
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "System Alarm LED"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    Off    ${Product_Name}

Perform Hot-swap the power module and power cord ten times, and verify the functions be listed on right side. 5
    [Documentation]    Hot-swap PSU under 'power on' state, check fail LED, beeper, and console status that can work properly.
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "Temperature Alarm LED"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    Off    ${Product_Name}

Perform Hot-swap the power module and power cord ten times, and verify the functions be listed on right side. 6
    [Documentation]    Hot-swap PSU under 'power on' state, check fail LED, beeper, and console status that can work properly.
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "Fan Alarm LED"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    Off    ${Product_Name}

大部分操作需要人工操作
    [Documentation]    大部分操作需要人工操作
    Log to console    ${\n}
    Log to console    大部分操作需要人工操作 --- 拔除 PSU1 的 Power cold
    Log to console    大部分操作需要人工操作 --- 拔除 PSU2 的 Power cold
    Log to console    大部分操作需要人工操作 --- 拔除 PSU1 的 Power Module
    Log to console    大部分操作需要人工操作 --- 拔除 PSU2 的 Power Module
    Log to console    ${\n}

Test Case sel list
    Set Suite Variable    ${file_name}    BMC_sel_list
    #${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe ${bmc_login} sel clear
    #${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 fru
    ${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe ${bmc_login} sel list
    Log to console    ${\n}
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}
    #${frt}    Run    type ${file_name}.txt | find "Product Name"
    #Log To Console    [${frt}]
    #${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    #Log To Console    [${Product_Name}]

    #Should Be Equal As Strings    J4024-05-04X    ${Product_Name}

Test Case sel elist
    Set Suite Variable    ${file_name}    BMC_sel_elist
    #${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe ${bmc_login} sel clear
    #${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 fru
    ${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe ${bmc_login} sel elist
    Log to console    ${\n}
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}
    #${frt}    Run    type ${file_name}.txt | find "Product Name"
    #Log To Console    [${frt}]
    #${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    #Log To Console    [${Product_Name}]

    #Should Be Equal As Strings    J4024-05-04X    ${Product_Name}

Open 192.168.11.11 --- Chrome
    Open Browser    https://192.168.11.11/    chrome    options=add_argument("--ignore-certificate-errors")
    Maximize Browser Window
    sleep    2
    Input Text    userid    admin
    Input Password    password    admin123
    Click Button    btn-login
    #Page Should Contain    Welcome,
    sleep    5
    Capture Page Screenshot

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
