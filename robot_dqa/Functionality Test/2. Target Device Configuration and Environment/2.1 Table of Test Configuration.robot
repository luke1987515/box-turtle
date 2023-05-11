*** Settings ***
Library     OperatingSystem
Library     String


*** Variables ***
${file_name}    file_with_variable


*** Test Cases ***
Test Case
    Log to console    hello, world.

Motherboard
    Set Suite Variable    ${file_name}    motherboard
    ${result}    Run    C:/ipmitool/ipmitool.exe fru
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}

Motherboard 1
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "Board Mfg"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log    [${Product_Name}]
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    AIC    ${Product_Name}

Motherboard 2
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "Board Product"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    ${SPACE}
    Log    [${Product_Name}]
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    TUCANA    ${Product_Name}

Operation System 1
    Log to console    ${\n}
    ${system}    Evaluate    platform.system()    platform
    log    [${system}]
    log to console    [${system}]

Operation System 2
    Set Suite Variable    ${file_name}    Operation_System
    ${result}    Run    systeminfo
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}

Operation System 3
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "OS Name"
    Log To Console    [${frt}]
    ${Product_Name}    Fetch From Right    ${frt}    Microsoft Windows${SPACE}
    Log    [${Product_Name}]
    Log To Console    [${Product_Name}]

    Should Be Equal As Strings    Server 2022 Datacenter    ${Product_Name}
