#!/bin/bash

# Chainlet management module

# Source shared utilities
source "$(dirname "${BASH_SOURCE[0]}")/shared.sh"

chainlet_print_usage() {
    log "Usage: cluster.sh chainlet SUBCOMMAND [OPTIONS]"
    log ""
    log "Chainlet management commands"
    log ""
    log "SUBCOMMANDS:"
    log "  restart <identifier>           Restart chainlet pods by namespace or chain_id"
    log "  redeploy <identifier>          Redeploy chainlet deployment by namespace or chain_id"
    log "  logs <identifier>              Follow logs for chainlet by namespace or chain_id"
    log "  status <identifier>            Show sync status for a specific chainlet"
    log "  expand-pvc <identifier> [%]    Expand chainlet PVC by percentage (default: 20%)"
    log ""
    log "EXAMPLES:"
    log "  cluster.sh chainlet restart saga-my-chain              # Restart using full namespace"
    log "  cluster.sh chainlet restart my_chain_id                # Restart using chain_id (converts to saga-my-chain-id)"
    log "  cluster.sh chainlet redeploy saga-my-chain             # Redeploy using full namespace"
    log "  cluster.sh chainlet redeploy my_chain_id               # Redeploy using chain_id"
    log "  cluster.sh chainlet logs saga-my-chain                 # Follow logs using full namespace"
    log "  cluster.sh chainlet logs my_chain_id                   # Follow logs using chain_id"
    log "  cluster.sh chainlet status saga-my-chain               # Check specific chainlet status"
    log "  cluster.sh chainlet status my_chain_id                 # Check specific chainlet status using chain_id"
    log "  cluster.sh chainlet expand-pvc saga-my-chain           # Expand PVC by 20% (default)"
    log "  cluster.sh chainlet expand-pvc my_chain_id 50          # Expand PVC by 50%"
}

chainlet_restart() {
    local identifier="$1"
    if [ -z "$identifier" ]; then
        error "restart command requires an identifier (namespace or chain_id)"
        echo ""
        chainlet_print_usage
        exit 1
    fi
    
    local namespace=$(get_namespace "$identifier")
    log "Restarting chainlet in namespace: $namespace"

    log_and_execute_cmd $KUBECTL delete pod -n "$namespace" -l app=chainlet

    if [ $? -eq 0 ]; then
        success "Chainlet pods in namespace '$namespace' restarted successfully"
        log "New pods will be created automatically by the deployment"
    else
        error "Failed to restart chainlet pods in namespace '$namespace'"
        exit 1
    fi
}

chainlet_redeploy() {
    local identifier="$1"
    if [ -z "$identifier" ]; then
        error "redeploy command requires an identifier (namespace or chain_id)"
        echo ""
        chainlet_print_usage
        exit 1
    fi
    
    local namespace=$(get_namespace "$identifier")

    if redeploy_chainlet_in_namespace "$namespace"; then
        log "New deployment will be created automatically by the controller"
    else
        exit 1
    fi
}


chainlet_logs() {
    local identifier="$1"
    if [ -z "$identifier" ]; then
        error "logs command requires an identifier (namespace or chain_id)"
        echo ""
        chainlet_print_usage
        exit 1
    fi
    
    local namespace=$(get_namespace "$identifier")
    log "Following logs for chainlet in namespace: $namespace"

    # Follow logs with exec (replaces current process)
    exec $KUBECTL logs -f deployment/chainlet -n "$namespace"
}

chainlet_status() {
    local identifier="$1"
    if [ -z "$identifier" ]; then
        error "status command requires an identifier (namespace or chain_id)"
        echo ""
        chainlet_print_usage
        exit 1
    fi
    
    local namespace=$(get_namespace "$identifier")
    log "Checking status for chainlet in namespace: $namespace"

    # Get chainlet status
    status=$($KUBECTL exec -n "$namespace" deployment/chainlet -- sagaosd status 2>/dev/null | jq -r '(.SyncInfo // .sync_info) | .catching_up' 2>/dev/null)

    case "$status" in
        "false")
            success "✅ In sync"
            ;;
        "true")
            warning "🟡 Syncing"
            ;;
        *)
            error "🔴 Offline"
            exit 1
            ;;
    esac
}


chainlet_expand_pvc() {
    local identifier="$1"
    local expand_percentage="${2:-20}"  # Default to 20%
    
    if [ -z "$identifier" ]; then
        error "expand-pvc command requires an identifier (namespace or chain_id)"
        echo ""
        chainlet_print_usage
        exit 1
    fi
    
    local namespace=$(get_namespace "$identifier")
    local pvc_name="chainlet-pvc"

    log "Expanding PVC '$pvc_name' in namespace '$namespace' by $expand_percentage%"

    # Check if PVC exists
    if ! $KUBECTL get pvc "$pvc_name" -n "$namespace" >/dev/null 2>&1; then
        error "PVC '$pvc_name' not found in namespace '$namespace'"
        exit 1
    fi

    # Get current PVC size
    current_size=$($KUBECTL get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.spec.resources.requests.storage}')
    if [ -z "$current_size" ]; then
        error "Failed to get current PVC size"
        exit 1
    fi

    log "Current PVC size: $current_size"

    # Extract numeric value and unit from size (e.g., "200Gi" -> "200" and "Gi")
    if [[ $current_size =~ ^([0-9]+)([A-Za-z]+)$ ]]; then
        size_value=${BASH_REMATCH[1]}
        size_unit=${BASH_REMATCH[2]}
    else
        error "Unable to parse current PVC size: $current_size"
        exit 1
    fi

    # Calculate new size
    new_size_value=$((size_value * (100 + expand_percentage) / 100))
    new_size="${new_size_value}${size_unit}"

    log "Expanding from $current_size to $new_size (${expand_percentage}% increase)"

    # Patch the PVC
    if $KUBECTL patch pvc "$pvc_name" -n "$namespace" -p "{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"$new_size\"}}}}"; then
        success "✅ PVC '$pvc_name' successfully expanded to $new_size"
        log "Note: The expansion may take a few moments to complete depending on your storage provider"

        # Restart chainlet pod to pick up the expanded storage
        log "Restarting chainlet pod to apply expanded storage..."
        if $KUBECTL delete pod -n "$namespace" -l app=chainlet >/dev/null 2>&1; then
            success "✅ Chainlet pod restarted successfully"
            log "New pod will be created automatically with expanded storage"
        else
            warning "⚠️ PVC expanded but failed to restart chainlet pod. You may need to restart manually."
        fi
    else
        error "Failed to expand PVC '$pvc_name'"
        exit 1
    fi
}

# Main chainlet command handler
handle_chainlet_command() {
    local subcommand="$1"
    shift  # Remove subcommand from arguments
    
    case "$subcommand" in
        restart)
            chainlet_restart "$1"
            ;;
        redeploy)
            chainlet_redeploy "$1"
            ;;
        logs)
            chainlet_logs "$1"
            ;;
        status)
            chainlet_status "$1"
            ;;
        expand-pvc)
            chainlet_expand_pvc "$1" "$2"
            ;;
        -h|--help|help|"")
            chainlet_print_usage
            ;;
        *)
            error "Unknown chainlet subcommand: $subcommand"
            echo ""
            chainlet_print_usage
            exit 1
            ;;
    esac
}
