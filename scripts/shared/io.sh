
# Function to ask for confirmation
confirm_action() {
    local message="$1"
    log "$message"
    read -p "Continue? (Y/n): " -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log "Operation cancelled"
        return 1
    fi
    return 0
}