on idle
    tell application "System Events"
        set isRunning to (name of processes) contains "longTerm"
        if isRunning is false then
            tell application "longTerm"
                activate
            end tell
        end if
    end tell
    return 10 -- Check every 10 seconds
end idle

on run
    tell application "System Events"
        set isRunning to (name of processes) contains "longTerm"
        if isRunning is false then
            tell application "longTerm"
                activate
            end tell
        end if
    end tell
end run
