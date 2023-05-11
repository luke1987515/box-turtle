try:
    from robot.libraries.BuiltIn import BuiltIn
    from robot.libraries.BuiltIn import _Misc
    import robot.api.logger as logger
    from robot.api.deco import keyword
    ROBOT = False
except Exception:
    ROBOT = False


# Import the libraries inputimeout, TimeoutOccurred
from inputimeout import inputimeout


@keyword("COSTOM KEYWORD TO INPUTIMEOUT")
def inputtimeout():
    # Try block of code
    # and handle errors
    try:
        # Take timed input using inputimeout() function
        time_over = inputimeout(prompt='Name your best friend:', timeout=3)
    # Catch the timeout error
    except Exception:
        # Declare the timeout statement
        time_over = 'Your time is over!'
    # Print the statement on timeoutprint(time_over)
    print(time_over)
    return time_over


inputtimeout()
