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

CPU 1
    Log to console    ${\n}
    ${system}    Evaluate    platform.machine()    platform
    log    [${system}]
    log to console    [${system}]

CPU 2
    Set Suite Variable    ${file_name}    CPU
    ${result}    Run    wmic cpu get name
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}

CPU 3
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "Intel"
    Log To Console    [${frt}]
    ${words}    Split String    ${frt}    ${SPACE}
    Log    [${words}[1]]
    Log To Console    [${words}[1]]

    Should Be Equal As Strings    Intel(R)    ${words}[1]

CPU 4
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "Intel"
    Log    ${frt}
    Log To Console    ${frt}

    Should Be Equal As Strings    Genuine Intel(R) CPU $0000%@${SPACE}${SPACE}    ${frt}

Memory 1
    Log to console    ${\n}
    ${system}    Run    wmic memorychip
    log    [${system}]
    log to console    [${system}]

Memory 2
    Set Suite Variable    ${file_name}    Memory
    ${result}    Run    wmic memorychip get Caption, Manufacturer, PartNumber
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}

Memory 3
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "Memory"
    Log To Console    [${frt}]
    ${words}    Split String    ${frt}    ${SPACE}
    Log    [${words}[3]]
    Log To Console    [${words}[3]]

    Should Be Equal As Strings    Micron    ${words}[3]

Memory 4
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "Memory"
    Log To Console    [${frt}]
    ${words}    Split String    ${frt}    ${SPACE}
    Log    [${words}[11]]
    Log To Console    [${words}[11]]

    Should Be Equal As Strings    36ASF4G72PZ-2G3B1    ${words}[11]

Hard Disk Drive 1
    Log to console    ${\n}
    ${system}    Run    wmic diskdrive
    log    [${system}]
    log to console    [${system}]

Hard Disk Drive 2
    Set Suite Variable    ${file_name}    Hard_Disk_Drive
    ${result}    Run    wmic diskdrive get MediaType, Model, SerialNumber, Size
    Log to console    ${result}
    Create File    ${EXECDIR}/${file_name}.txt    ${result}

Hard Disk Drive 3
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "disk"
    Log To Console    [${frt}]
    ${words}    Split String    ${frt}    ${SPACE}
    Log    [${words}[5]]
    Log To Console    [${words}[5]]

    Should Be Equal As Strings    SAMSUNG    ${words}[5]

Hard Disk Drive 4
    Log to console    ${\n}
    ${frt}    Run    type ${file_name}.txt | find "disk"
    Log To Console    [${frt}]
    ${words}    Split String    ${frt}    ${SPACE}
    Log    [${words}[6]]
    Log To Console    [${words}[6]]

    Should Be Equal As Strings    MZ7GE480HMHP-00003    ${words}[6]
