#!/bin/bash

source "$(dirname "$0")/shared/log.sh"
source "$(dirname "$0")/shared/io.sh"

print_usage() {
    log "Usage: $0 [OPTIONS] COMMAND"
    log ""
    log "Execute operations on the Saga cluster"
    log ""
    log "OPTIONS:"
    log "  --kubeconfig PATH    Path to kubeconfig file (optional)"
    log "  -h, --help          Show this help message"
    log ""
    log "COMMANDS:"
    log "  scale-down-controller          Scale down the controller deployment"
    log "  scale-up-controller            Scale up the controller deployment"
    log "  restart-controller             Restart controller pod"
    log "  restart-chainlet <identifier>  Restart chainlet pods by namespace or chain_id"
    log "  redeploy-chainlet <identifier> Redeploy chainlet deployment by namespace or chain_id"
    log "  redeploy-all-chainlets         Redeploy all chainlet deployments in saga-* namespaces"
    log "  logs <identifier>              Follow logs for chainlet by namespace or chain_id"
    log "  chainlets-status               Show status of all chainlets"
    log "  install-completion             Install bash completion for this script"
    log ""
    log "EXAMPLES:"
    log "  $0 scale-down-controller                        # Scale down using default kubeconfig"
    log "  $0 --kubeconfig ~/.kube/config scale-up-controller   # Scale up using specific kubeconfig"
    log "  $0 restart-controller                          # Restart controller pod"
    log "  $0 restart-chainlet saga-my-chain              # Restart using full namespace"
    log "  $0 restart-chainlet my_chain_id                # Restart using chain_id (converts to saga-my-chain-id)"
    log "  $0 redeploy-chainlet saga-my-chain             # Redeploy using full namespace"
    log "  $0 redeploy-chainlet my_chain_id               # Redeploy using chain_id"
    log "  $0 redeploy-all-chainlets                      # Redeploy all chainlets"
    log "  $0 logs saga-my-chain                          # Follow logs using full namespace"
    log "  $0 logs my_chain_id                            # Follow logs using chain_id"
    log "  $0 chainlets-status                            # Show chainlets status"
    log "  $0 install-completion                          # Install bash completion"
}

log_and_execute_cmd() {
    log "$*"
    eval "$*"
}

# Shared function to get namespace from identifier
get_namespace() {
    local identifier="$1"
    if [[ "$identifier" == saga-* ]]; then
        # Already a namespace format
        echo "$identifier"
    else
        # Convert chain_id to namespace format (replace _ with -, add saga- prefix)
        echo "saga-${identifier//_/-}"
    fi
}

# Shared function to redeploy chainlet in a specific namespace
redeploy_chainlet_in_namespace() {
    local namespace="$1"
    log "Redeploying chainlet in namespace: $namespace"

    log_and_execute_cmd $KUBECTL delete deployment chainlet -n "$namespace"

    if [ $? -eq 0 ]; then
        success "Chainlet deployment in namespace '$namespace' deleted successfully"
    else
        error "Failed to delete chainlet deployment in namespace '$namespace'"
        return 1
    fi
    return 0
}

# Parse command line arguments
KUBECONFIG_FILE=""
COMMAND=""
CHAINLET_IDENTIFIER=""

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
        scale-down-controller|scale-up-controller|restart-controller|redeploy-all-chainlets|chainlets-status|install-completion)
            COMMAND="$1"
            shift
            ;;
        restart-chainlet|redeploy-chainlet|logs)
            COMMAND="$1"
            if [[ $# -lt 2 ]]; then
                error "$1 command requires an identifier (namespace or chain_id)"
                echo ""
                print_usage
                exit 1
            fi
            CHAINLET_IDENTIFIER="$2"
            shift 2
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

# Set kubectl command with optional kubeconfig
if [ -n "$KUBECONFIG_FILE" ]; then
    if [ ! -f "$KUBECONFIG_FILE" ]; then
        error "Kubeconfig file not found: $KUBECONFIG_FILE"
        exit 1
    fi
    KUBECTL="kubectl --kubeconfig=$KUBECONFIG_FILE"
    log "Using kubeconfig: $KUBECONFIG_FILE"
else
    KUBECTL="kubectl"
    log "Using current context: $($KUBECTL config current-context)"
fi

# Execute commands
case "$COMMAND" in
    scale-down-controller)
        log "Scaling down controller..."
        log_and_execute_cmd $KUBECTL scale deployment/controller -n sagasrv-controller --replicas=0
        if [ $? -eq 0 ]; then
            success "Controller scaled down successfully. Don't forget to $0 scale-up-controller"
        else
            error "Failed to scale down controller"
            exit 1
        fi
        ;;
    scale-up-controller)
        log "Scaling up controller..."
        log_and_execute_cmd $KUBECTL scale deployment/controller -n sagasrv-controller --replicas=1
        if [ $? -eq 0 ]; then
            success "Controller scaled up successfully"
        else
            error "Failed to scale up controller"
            exit 1
        fi
        ;;
    restart-controller)
        log "Restarting controller..."
        log_and_execute_cmd $KUBECTL delete pod -n sagasrv-controller -l app=controller

        if [ $? -eq 0 ]; then
            success "Controller pod restarted successfully"
            log "New pod will be created automatically by the deployment"
        else
            error "Failed to restart controller pod"
            exit 1
        fi
        ;;
    restart-chainlet)
        NAMESPACE=$(get_namespace "$CHAINLET_IDENTIFIER")
        log "Restarting chainlet in namespace: $NAMESPACE"

        log_and_execute_cmd $KUBECTL delete pod -n "$NAMESPACE" -l app=chainlet
        
        if [ $? -eq 0 ]; then
            success "Chainlet pods in namespace '$NAMESPACE' restarted successfully"
            log "New pods will be created automatically by the deployment"
        else
            error "Failed to restart chainlet pods in namespace '$NAMESPACE'"
            exit 1
        fi
        ;;
    redeploy-chainlet)
        NAMESPACE=$(get_namespace "$CHAINLET_IDENTIFIER")
        
        if redeploy_chainlet_in_namespace "$NAMESPACE"; then
            log "New deployment will be created automatically by the controller"
        else
            exit 1
        fi
        ;;
    logs)
        NAMESPACE=$(get_namespace "$CHAINLET_IDENTIFIER")
        log "Following logs for chainlet in namespace: $NAMESPACE"
        
        # Follow logs with exec (replaces current process)
        exec $KUBECTL logs -f deployment/chainlet -n "$NAMESPACE"
        ;;
    redeploy-all-chainlets)
        # Check if controller is running
        if ! $KUBECTL get pods -n sagasrv-controller -l app=controller | grep -q "Running"; then
            error "Controller is not running. Please ensure controller is up before redeploying chainlets."
            log "Run: $0 scale-up-controller"
            exit 1
        fi

        # Get all saga-* namespaces that contain chainlet deployments
        CHAINLET_NAMESPACES=($($KUBECTL get deployment -A | grep chainlet | grep ^saga- | awk '{print $1}'))

        if [ ${#CHAINLET_NAMESPACES[@]} -eq 0 ]; then
            warning "No chainlet deployments found"
            exit 0
        fi

        if [ ${#CHAINLET_NAMESPACES[@]} -eq 0 ]; then
            warning "No chainlet deployments found in saga-* namespaces"
            exit 0
        fi

        log "Found chainlet deployments in ${#CHAINLET_NAMESPACES[@]} namespace(s):"
        for ns in "${CHAINLET_NAMESPACES[@]}"; do
            log "  - $ns"
        done

        log ""
        if ! confirm_action "⚠️⚠️⚠️ This will redeploy ALL chainlet deployments in the above namespaces and will cause ${BOLD}DOWNTIME${NC}"; then
            exit 0
        fi

        # Redeploy all chainlets
        failed_count=0
        success_count=0

        for ns in "${CHAINLET_NAMESPACES[@]}"; do
            if redeploy_chainlet_in_namespace "$ns"; then
                ((success_count++))
            else
                ((failed_count++))
            fi
        done

        log ""
        if [ $failed_count -eq 0 ]; then
            success "✅ Successfully redeployed all $success_count chainlet deployments"
            log "New deployments will be created automatically by the controller"
        else
            error "❌ $success_count succeeded, $failed_count failed"
            exit 1
        fi
        ;;
    chainlets-status)
        SCRIPT_DIR="$(dirname "$0")"
        CHAINLETS_STATUS_SCRIPT="$SCRIPT_DIR/cmd/chainlets-status.sh"

        if [ ! -f "$CHAINLETS_STATUS_SCRIPT" ]; then
            error "chainlets-status.sh script not found at: $CHAINLETS_STATUS_SCRIPT"
            exit 1
        fi

        # Build command with optional kubeconfig
        if [ -n "$KUBECONFIG_FILE" ]; then
            exec "$CHAINLETS_STATUS_SCRIPT" --kubeconfig "$KUBECONFIG_FILE"
        else
            exec "$CHAINLETS_STATUS_SCRIPT"
        fi
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
esac
