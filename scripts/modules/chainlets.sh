#!/bin/bash

# Chainlets management module (for operations on all chainlets)

# Source shared utilities
source "$(dirname "${BASH_SOURCE[0]}")/shared.sh"

chainlets_print_usage() {
    log "Usage: cluster.sh chainlets SUBCOMMAND"
    log ""
    log "Chainlets management commands (operations on all chainlets)"
    log ""
    log "SUBCOMMANDS:"
    log "  status      Show status of all chainlets"
    log "  redeploy    Redeploy all chainlet deployments in saga-* namespaces"
    log "  versions    Show chainletStackVersion for all online chainlets"
    log ""
    log "EXAMPLES:"
    log "  cluster.sh chainlets status                            # Show all chainlets status"
    log "  cluster.sh chainlets redeploy                          # Redeploy all chainlets"
    log "  cluster.sh chainlets versions                          # Show stack versions of online chainlets"
}

chainlets_status() {
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")/.."
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
}

chainlets_redeploy() {
    # Check if controller is running
    if ! $KUBECTL get pods -n sagasrv-controller -l app=controller | grep -q "Running"; then
        error "Controller is not running. Please ensure controller is up before redeploying chainlets."
        log "Run: cluster.sh controller up"
        exit 1
    fi

    # Get all saga-* namespaces that contain chainlet deployments
    CHAINLET_NAMESPACES=($($KUBECTL get deployment -A | grep chainlet | grep ^saga- | awk '{print $1}'))

    if [ ${#CHAINLET_NAMESPACES[@]} -eq 0 ]; then
        warning "No chainlet deployments found"
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
}

chainlets_versions() {
    # Fetch all online chainlets from SSC and print chainletStackVersion
    if ! $KUBECTL get deployment/ssc -n sagasrv-ssc >/dev/null 2>&1; then
        error "SSC deployment not found in namespace 'sagasrv-ssc'"
        exit 1
    fi

    local chainlets_json
    if ! chainlets_json=$($KUBECTL exec -n sagasrv-ssc deployment/ssc -- sscd q chainlet list-chainlets --limit 1000 --output json 2>/dev/null); then
        error "Failed to fetch chainlets list from SSC"
        exit 1
    fi

    local count
    count=$(echo "$chainlets_json" | jq -r '[.Chainlets[]? | select(.status == "STATUS_ONLINE")] | length' 2>/dev/null)
    if [ -z "$count" ] || [ "$count" = "null" ]; then
        error "Failed to parse chainlets list output"
        exit 1
    fi

    if [ "$count" -eq 0 ]; then
        warning "No online chainlets found"
        exit 0
    fi

    # Print one per line: "<chainId> <chainletStackVersion (bold)>"
    while IFS=$'\t' read -r chain_id stack_version; do
        if [ -n "$chain_id" ]; then
            log "${chain_id} ${BOLD}${stack_version}${NC}"
        fi
    done < <(
        echo "$chainlets_json" | jq -r '
          .Chainlets[]
          | select(.status == "STATUS_ONLINE")
          | "\(.chainId)\t\(.chainletStackVersion // "")"
        ' 2>/dev/null
    )
}

# Main chainlets command handler
handle_chainlets_command() {
    local subcommand="$1"
    
    case "$subcommand" in
        status)
            chainlets_status
            ;;
        redeploy)
            chainlets_redeploy
            ;;
        versions)
            chainlets_versions
            ;;
        -h|--help|help|"")
            chainlets_print_usage
            ;;
        *)
            error "Unknown chainlets subcommand: $subcommand"
            echo ""
            chainlets_print_usage
            exit 1
            ;;
    esac
}
