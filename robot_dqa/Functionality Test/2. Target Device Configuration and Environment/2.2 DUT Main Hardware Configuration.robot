*** Settings ***
Library     OperatingSystem
Library     String


*** Variables ***
${bmc_login}    -I lanplus -H 192.168.11.11 -U admin -P admin123
${file_name}    file_with_variable


*** Test Cases ***
BMC 1
    Set Suite Variable    ${file_name}    BMC_name
    #${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 fru
    ${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe ${bmc_login} raw 0x3a 0x33
    Log to console    ${\n}
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}
    ${frt}    Run    type ${file_name}.txt
    Log To Console    [${frt}]
    ${bytes}    Convert To Bytes    ${frt}    hex
    Log To Console    [${bytes}]

    Should Be Equal As Strings    4203JBD011503    ${bytes}

BMC - mc selftest
    Set Suite Variable    ${file_name}    BMC_mc_selftest
    #${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 mc info
    ${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe ${bmc_login} mc selftest
    Log to console    ${\n}
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}
    ${frt}    Run    type ${file_name}.txt | find "Selftest"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    passed    ${Product_Name}
