#!/bin/bash

# Source shared utilities and modules
source "$(dirname "$0")/shared/log.sh"
source "$(dirname "$0")/shared/io.sh"
source "$(dirname "$0")/modules/shared.sh"
source "$(dirname "$0")/modules/controller.sh"
source "$(dirname "$0")/modules/chainlet.sh"
source "$(dirname "$0")/modules/chainlets.sh"

print_usage() {
    log "Usage: $0 [OPTIONS] COMMAND [SUBCOMMAND] [ARGS...]"
    log ""
    log "Execute operations on the Saga cluster"
    log ""
    log "OPTIONS:"
    log "  --kubeconfig PATH    Path to kubeconfig file (optional)"
    log "  -h, --help          Show this help message"
    log ""
    log "COMMANDS:"
    log "  controller           Controller management commands"
    log "  chainlet             Individual chainlet management commands"
    log "  chainlets            All chainlets management commands"
    log "  install-completion   Install bash completion for this script"
    log ""
    log "Use '$0 COMMAND --help' to see subcommands for each command."
    log ""
    log "EXAMPLES:"
    log "  $0 controller scale-down                        # Scale down controller"
    log "  $0 controller scale-up                          # Scale up controller"
    log "  $0 controller restart                           # Restart controller pod"
    log "  $0 chainlet restart saga-my-chain               # Restart chainlet using full namespace"
    log "  $0 chainlet restart my_chain_id                 # Restart chainlet using chain_id"
    log "  $0 chainlet redeploy saga-my-chain              # Redeploy chainlet using full namespace"
    log "  $0 chainlet redeploy saga-my-chain              # Redeploy chainlet using full namespace"
    log "  $0 chainlet logs saga-my-chain                  # Follow chainlet logs"
    log "  $0 chainlet status saga-my-chain                # Check specific chainlet status"
    log "  $0 chainlets status                             # Show all chainlets status"
    log "  $0 chainlets redeploy                           # Redeploy all chainlets"
    log "  $0 chainlet expand-pvc saga-my-chain            # Expand PVC by 20% (default)"
    log "  $0 chainlet expand-pvc my_chain_id 50           # Expand PVC by 50%"
    log "  $0 install-completion                           # Install bash completion"
}

# Parse command line arguments
KUBECONFIG_FILE=""
COMMAND=""
SUBCOMMAND=""
REMAINING_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --kubeconfig)
            KUBECONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        controller|chainlet|chainlets|install-completion)
            COMMAND="$1"
            shift
            # Capture subcommand and remaining arguments
            if [[ $# -gt 0 ]]; then
                SUBCOMMAND="$1"
                shift
                REMAINING_ARGS=("$@")
            fi
            break
            ;;
        *)
            error "Unknown option/command: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
done

if [ -z "$COMMAND" ]; then
    error "No command specified"
    echo ""
    print_usage
    exit 1
fi

# Setup kubectl with optional kubeconfig
setup_kubectl "$KUBECONFIG_FILE"

# Execute commands
case "$COMMAND" in
    controller)
        handle_controller_command "$SUBCOMMAND" "${REMAINING_ARGS[@]}"
        ;;
    chainlet)
        handle_chainlet_command "$SUBCOMMAND" "${REMAINING_ARGS[@]}"
        ;;
    chainlets)
        handle_chainlets_command "$SUBCOMMAND" "${REMAINING_ARGS[@]}"
        ;;
    install-completion)
        SCRIPT_DIR="$(dirname "$0")"
        COMPLETION_SCRIPT="$SCRIPT_DIR/config/cluster-completion.bash"

        if [ ! -f "$COMPLETION_SCRIPT" ]; then
            error "Completion script not found at: $COMPLETION_SCRIPT"
            exit 1
        fi

        # Determine completion directory
        if [ -d "/usr/local/etc/bash_completion.d" ]; then
            COMPLETION_DIR="/usr/local/etc/bash_completion.d"
        elif [ -d "/etc/bash_completion.d" ]; then
            COMPLETION_DIR="/etc/bash_completion.d"
        elif [ -d "$HOME/.local/share/bash-completion/completions" ]; then
            COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
        else
            # Create user completion directory if none exists
            COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
            mkdir -p "$COMPLETION_DIR"
        fi

        COMPLETION_FILE="$COMPLETION_DIR/cluster.sh"

        log "Installing bash completion to: $COMPLETION_FILE"

        if cp "$COMPLETION_SCRIPT" "$COMPLETION_FILE"; then
            success "✅ Bash completion installed successfully"
            log ""
            log "To enable completion in your current session, run:"
            log "  source $COMPLETION_FILE"
            log ""
            log "To enable completion permanently, add this to your ~/.bashrc:"
            log "  source $COMPLETION_FILE"
            log ""
            log "Or restart your shell to use the system-wide completion."
        else
            error "Failed to install completion script"
            log "You may need to run with sudo for system-wide installation:"
            log "  sudo $0 install-completion"
            exit 1
        fi
        ;;
    *)
        error "Unknown command: $COMMAND"
        echo ""
        print_usage
        exit 1
        ;;
esac
