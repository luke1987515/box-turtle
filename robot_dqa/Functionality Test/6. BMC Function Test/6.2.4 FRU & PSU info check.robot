*** Settings ***
Library     OperatingSystem
Library     String


*** Variables ***
${file_name}    file_with_variable


*** Test Cases ***
Test Case fru
    Set Suite Variable    ${file_name}    BMC_fru_info
    ${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 fru
    Log to console    ${\n}    
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}
    ${frt}    Run    type ${file_name}.txt | find "Product Name"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    J4024-05-04X    ${Product_Name}

Test Case2 mc info
    Set Suite Variable    ${file_name}    BMC_mc_info
    ${result}    Run    ${EXECDIR}/tool/ipmitool-1.8.18-cygwin-binary/ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 mc info
    Log to console    ${\n}
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}
    ${frt}    Run    type ${file_name}.txt | find "Product Name"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    (0x4203)    ${Product_Name}