#!/bin/bash

# SSC management module

# Source shared utilities
source "$(dirname "${BASH_SOURCE[0]}")/shared.sh"

ssc_print_usage() {
    log "Usage: cluster.sh ssc SUBCOMMAND"
    log ""
    log "SSC management commands"
    log ""
    log "SUBCOMMANDS:"
    log "  status      Show SSC sync status"
}

ssc_status() {
    local namespace="sagasrv-ssc"
    log "Checking status for SSC in namespace: $namespace"

    # Get SSC status
    status=$($KUBECTL exec -n "$namespace" deployment/ssc -- sscd status 2>/dev/null | jq -r '(.SyncInfo // .sync_info) | .catching_up' 2>/dev/null)

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

# Main ssc command handler
handle_ssc_command() {
    local subcommand="$1"

    case "$subcommand" in
        status)
            ssc_status
            ;;
        -h|--help|help|"")
            ssc_print_usage
            ;;
        *)
            error "Unknown ssc subcommand: $subcommand"
            echo ""
            ssc_print_usage
            exit 1
            ;;
    esac
}


