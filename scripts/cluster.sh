#!/bin/bash

# Source shared logging functions
source "$(dirname "$0")/shared/log.sh"

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
    log "  scale-up-controller           Scale up the controller deployment"
    log "  restart-chainlet <identifier>  Restart chainlet pods by namespace or chain_id"
    log "  redeploy-chainlet <identifier> Redeploy chainlet deployment by namespace or chain_id"
    log ""
    log "EXAMPLES:"
    log "  $0 scale-down-controller                        # Scale down using default kubeconfig"
    log "  $0 --kubeconfig ~/.kube/config scale-up-controller   # Scale up using specific kubeconfig"
    log "  $0 restart-chainlet saga-my-chain              # Restart using full namespace"
    log "  $0 restart-chainlet my_chain_id                # Restart using chain_id (converts to saga-my-chain-id)"
    log "  $0 redeploy-chainlet saga-my-chain             # Redeploy using full namespace"
    log "  $0 redeploy-chainlet my_chain_id               # Redeploy using chain_id"
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
        scale-down-controller|scale-up-controller)
            COMMAND="$1"
            shift
            ;;
        restart-chainlet|redeploy-chainlet)
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
        log "Redeploying chainlet in namespace: $NAMESPACE"

        log_and_execute_cmd $KUBECTL delete deployment chainlet -n "$NAMESPACE"
        
        if [ $? -eq 0 ]; then
            success "Chainlet deployment in namespace '$NAMESPACE' deleted successfully"
            log "New deployment will be created automatically by the controller"
        else
            error "Failed to delete chainlet deployment in namespace '$NAMESPACE'"
            exit 1
        fi
        ;;
esac
