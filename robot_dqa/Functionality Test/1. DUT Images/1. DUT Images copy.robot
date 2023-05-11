*** Settings ***
Library     OperatingSystem
Library     Dialogs
Library     input_timeout.py


*** Test Cases ***
Test Case
    Log to console    hello, world.

# Get User Input Test
#    ${input}=    Get Value From User    Enter a value:    default value
#    Log    Input value: ${input}
#    Log to console    Input value: ${input}

Get User Input Test2
    Log to console    ${\n}
    Log to console    Front 45 Angle
    Log to console    Top View
    Log to console    Rear View
    Log to console    上述三張照片都正確嗎？
    sleep    1
    Log to console    你只有 3 秒鐘!!!(輸入:y)
    Log to console    YOU HAVE ONELY 3 SEC!!!(Answer:y)
    ${input}=    COSTOM KEYWORD TO INPUTIMEOUT
    Should Be Equal    ${input}    y

# Get User Input Test3
#    ${input}=    Get Value From User    Enter a value:    Your time is over!
#    Log    Input value: ${input}
#    Should Be Equal    ${input}    Your time is over!

# *** Keywords ***
# Example Test
#    ${user_input}=    Get Value From User    Enter your input:    default value
#    Log    User input: ${user_input}
#    Log to console    Input value: ${user_input}
