on run {input, parameters}
    -- Set the app name to monitor
    set appName to "longTerm"
    
    -- Create a loop that runs indefinitely
    repeat
        -- Check if the app is running
        set isRunning to false
        tell application "System Events"
            if exists (processes where name is appName) then
                set isRunning to true
            end if
        end tell
        
        -- If the app is not running, launch it
        if not isRunning then
            try
                tell application appName
                    activate
                end tell
                log "Restarted " & appName & " at " & (current date) as string
            on error errMsg
                log "Error launching " & appName & ": " & errMsg
            end try
        end if
        
        -- Wait before checking again (5 seconds)
        delay 5
    end repeat
    
    return input
end run
