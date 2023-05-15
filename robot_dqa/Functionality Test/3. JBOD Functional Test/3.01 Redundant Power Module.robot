*** Settings ***
Library     OperatingSystem
Library     String


*** Variables ***
${bmc_login}    -I lanplus -H 192.168.11.11 -U admin -P admin123
${file_name}    file_with_variable


*** Test Cases ***
Perform Hot-swap the power module and power cord ten times, and verify the functions be listed on right side. 1
    [Documentation]    Hot-swap PSU under 'power on' state, check fail LED, beeper, and console status that can work properly.
    Set Suite Variable    ${file_name}    EXP_console
    #${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 fru
    ${result}    Run    del /S EXP_console.txt
    ${result}    Run
    ...    ${EXECDIR}/tool/teraterm-4.106/ttermpro.exe /I /C=3 /BAUD=38400 /L=${EXECDIR}/${file_name}.txt /M=exp_sensor.ttl
    Log to console    ${\n}
    Log to console    ${result}
    #Create File    ${EXECDIR}/${file_name}.txt    ${result}
    ${frt}    Run    type ${file_name}.txt | find "PSU1 Status"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    Ok    ${Product_Name}
