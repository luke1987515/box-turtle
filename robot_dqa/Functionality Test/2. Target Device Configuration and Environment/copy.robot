*** Settings ***
Library           RPA.Browser.Selenium

*** Tasks ***
Get browser information
    Open Available Browser    https://developer.mozilla.org/
    ${info}=
    ...    Execute Javascript
    ...    return navigator.userAgent;