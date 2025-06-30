#!/bin/bash

# Configuration
APP_PATH="/Applications/longTerm.app"
WATCHDOG_PATH="/Library/LaunchDaemons/com.longterm.protection.plist"
PROTECTOR_PATH="/usr/local/bin/longterm_protector.sh"
BACKUP_PATH="/usr/local/share/longterm_backup.tar.gz"
TOKEN_PATH="/var/db/.longterm_token"
LOG_PATH="/var/log/longterm_protection.log"

# Time-based restrictions (24-hour format)
ALLOWED_START_HOUR=9
ALLOWED_END_HOUR=17
ALLOWED_DAYS="1,2,3,4,5" # Monday-Friday

# Authentication
SECRET_KEY="LT2025SecureKey"
REQUIRED_PHRASE="I CONFIRM DELETION OF LONGTERM APP"
COOLDOWN_DAYS=7 # Days required between unprotection attempts

# Function to check if current time is allowed
check_time_allowed() {
    current_hour=$(date +"%H")
    current_day=$(date +"%u") # 1-7, Monday is 1
    
    if [[ "$ALLOWED_DAYS" == *"$current_day"* ]] && 
       [ "$current_hour" -ge "$ALLOWED_START_HOUR" ] && 
       [ "$current_hour" -lt "$ALLOWED_END_HOUR" ]; then
        return 0 # Time is allowed
    else
        return 1 # Time is not allowed
    fi
}

# Create the protector script
create_protector_script() {
    cat > /tmp/longterm_protector.sh << 'EOL'
#!/bin/bash
APP_PATH="/Applications/longTerm.app"
BACKUP_PATH="/usr/local/share/longterm_backup.tar.gz"
TOKEN_PATH="/var/db/.longterm_token"
LOG_PATH="/var/log/longterm_protection.log"

log_message() {
    echo "$(date): $1" >> "$LOG_PATH"
}

# Check if token exists and is valid
if [ -f "$TOKEN_PATH" ]; then
    token_time=$(stat -f "%m" "$TOKEN_PATH")
    current_time=$(date +%s)
    time_diff=$((current_time - token_time))
    
    if [ $time_diff -gt 300 ]; then # 5 minutes
        rm -f "$TOKEN_PATH"
        log_message "Token expired and removed"
    fi
fi

# If app doesn't exist and we have a backup, restore it
if [ ! -d "$APP_PATH" ] && [ -f "$BACKUP_PATH" ]; then
    log_message "App missing - restoring from backup"
    mkdir -p "$APP_PATH"
    tar -xzf "$BACKUP_PATH" -C /Applications/
    chflags schg "$APP_PATH"
    chmod 555 "$APP_PATH"
    log_message "App restored and protected"
fi

# If app exists and no valid token, ensure protection
if [ -d "$APP_PATH" ] && [ ! -f "$TOKEN_PATH" ]; then
    log_message "Reapplying protection"
    chflags schg "$APP_PATH" 2>/dev/null
    chmod 555 "$APP_PATH" 2>/dev/null
fi
EOL
    sudo mv /tmp/longterm_protector.sh "$PROTECTOR_PATH"
    sudo chmod +x "$PROTECTOR_PATH"
}

# Create the LaunchDaemon
create_launch_daemon() {
    cat > /tmp/com.longterm.protection.plist << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.longterm.protection</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$PROTECTOR_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOL
    sudo mv /tmp/com.longterm.protection.plist "$WATCHDOG_PATH"
    sudo chown root:wheel "$WATCHDOG_PATH"
    sudo chmod 644 "$WATCHDOG_PATH"
}

# Install the protection system
install_protection() {
    echo "Installing advanced protection system for longTerm.app..."
    
    # Create backup of the app
    if [ -d "$APP_PATH" ]; then
        echo "Creating app backup..."
        sudo mkdir -p $(dirname "$BACKUP_PATH")
        sudo tar -czf "$BACKUP_PATH" -C /Applications/ longTerm.app
        sudo chmod 600 "$BACKUP_PATH"
    else
        echo "Error: App not found at $APP_PATH"
        exit 1
    fi
    
    # Create protector script
    create_protector_script
    
    # Create and load LaunchDaemon
    create_launch_daemon
    sudo launchctl load "$WATCHDOG_PATH"
    
    # Apply initial protection
    sudo chflags schg "$APP_PATH"
    sudo chmod 555 "$APP_PATH"
    
    # Create cooldown tracker file
    sudo touch "/var/db/.longterm_last_unprotect"
    
    echo "Protection system installed successfully."
    echo "The app is now protected against both accidental and intentional deletion."
    echo "To temporarily disable protection (valid for 5 minutes), use: $0 unprotect"
}

# Temporarily unprotect the app
unprotect_app() {
    # Check if we're within the cooldown period
    if [ -f "/var/db/.longterm_last_unprotect" ]; then
        last_time=$(stat -f "%m" "/var/db/.longterm_last_unprotect")
        current_time=$(date +%s)
        days_diff=$(( (current_time - last_time) / 86400 ))
        
        if [ $days_diff -lt $COOLDOWN_DAYS ]; then
            echo "Error: Cooldown period active. You must wait $COOLDOWN_DAYS days between unprotection attempts."
            echo "Days remaining: $(( COOLDOWN_DAYS - days_diff ))"
            return 1
        fi
    fi
    
    # Check if current time is allowed
    if ! check_time_allowed; then
        echo "Error: Unprotection is only allowed Monday-Friday between ${ALLOWED_START_HOUR}:00 and ${ALLOWED_END_HOUR}:00"
        echo "Current time: $(date +"%A %H:%M")"
        return 1
    fi
    
    # Verify passphrase
    echo -n "Enter the exact confirmation phrase: "
    read input_phrase
    
    if [ "$input_phrase" != "$REQUIRED_PHRASE" ]; then
        echo "Error: Incorrect confirmation phrase."
        return 1
    fi
    
    # Verify secret key
    echo -n "Enter the secret key: "
    read -s input_key
    echo
    
    if [ "$input_key" != "$SECRET_KEY" ]; then
        echo "Error: Incorrect secret key."
        return 1
    fi
    
    # Final confirmation with countdown
    echo "WARNING: You are about to disable protection for the longTerm app."
    echo "This will create a 5-minute window where the app can be modified or deleted."
    echo "Proceeding in 10 seconds... Press Ctrl+C to cancel."
    for i in {10..1}; do
        echo -n "$i... "
        sleep 1
    done
    echo "Proceeding."
    
    # Remove protection
    sudo chflags noschg "$APP_PATH"
    sudo chmod 755 "$APP_PATH"
    
    # Create token file
    echo "$(date)" | sudo tee "$TOKEN_PATH" > /dev/null
    sudo chmod 600 "$TOKEN_PATH"
    
    # Update last unprotect time
    sudo touch "/var/db/.longterm_last_unprotect"
    
    echo "TEMPORARY UNPROTECTION ACTIVATED"
    echo "You have 5 minutes to modify or delete the app."
    echo "After 5 minutes, protection will automatically reactivate."
    echo "The watchdog will attempt to restore the app if deleted."
}

# Remove the protection system (emergency use only)
remove_protection() {
    echo "WARNING: This will completely remove all protection systems."
    echo "The app will no longer be protected from deletion."
    
    # Triple confirmation
    echo -n "Type 'REMOVE ALL PROTECTION' to confirm: "
    read confirm1
    
    if [ "$confirm1" != "REMOVE ALL PROTECTION" ]; then
        echo "Operation cancelled."
        return 1
    fi
    
    echo -n "Enter the confirmation phrase: "
    read confirm2
    
    if [ "$confirm2" != "$REQUIRED_PHRASE" ]; then
        echo "Operation cancelled."
        return 1
    fi
    
    echo -n "Enter the secret key: "
    read -s confirm3
    echo
    
    if [ "$confirm3" != "$SECRET_KEY" ]; then
        echo "Operation cancelled."
        return 1
    fi
    
    # Unload and remove LaunchDaemon
    sudo launchctl unload "$WATCHDOG_PATH" 2>/dev/null
    sudo rm -f "$WATCHDOG_PATH"
    
    # Remove protector script
    sudo rm -f "$PROTECTOR_PATH"
    
    # Remove backup
    sudo rm -f "$BACKUP_PATH"
    
    # Remove token and tracking files
    sudo rm -f "$TOKEN_PATH"
    sudo rm -f "/var/db/.longterm_last_unprotect"
    
    # Remove protection from app
    sudo chflags noschg "$APP_PATH" 2>/dev/null
    sudo chmod 755 "$APP_PATH" 2>/dev/null
    
    echo "Protection system completely removed."
}

# Main script logic
case "$1" in
    install)
        install_protection
        ;;
    unprotect)
        unprotect_app
        ;;
    remove)
        remove_protection
        ;;
    *)
        echo "Usage: $0 {install|unprotect|remove}"
        echo
        echo "This script provides extreme protection against both accidental and intentional"
        echo "deletion of the longTerm.app, even with administrator privileges."
        echo
        echo "Protection features:"
        echo "- System immutable flags prevent modification even by root"
        echo "- Watchdog daemon runs every minute to verify and restore protection"
        echo "- Auto-restoration if app is deleted"
        echo "- Time-based restrictions (only workdays during business hours)"
        echo "- 7-day cooldown between unprotection attempts"
        echo "- Multiple verification factors required to disable protection"
        exit 1
        ;;
esac

exit 0
