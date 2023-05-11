*** Settings ***
Library     OperatingSystem
Library     Dialogs


*** Test Cases ***
Test Case
    Log to console    hello, world.

# Get User Input Test
#     ${input}=    Get Value From User    Enter a value:    default value
#     Log    Input value: ${input}
#     Log to console    Input value: ${input}


# *** Keywords ***
# Example Test
#     ${user_input}=    Get Value From User    Enter your input:    default value
#     Log    User input: ${user_input}
#     Log to console    Input value: ${user_input}
