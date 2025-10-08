#!/bin/bash

# Shared utilities for cluster management modules

# Source logging and IO utilities
source "$(dirname "${BASH_SOURCE[0]}")/../shared/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../shared/io.sh"

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

# Function to setup kubectl command with optional kubeconfig
setup_kubectl() {
    local kubeconfig_file="$1"
    
    if [ -n "$kubeconfig_file" ]; then
        if [ ! -f "$kubeconfig_file" ]; then
            error "Kubeconfig file not found: $kubeconfig_file"
            exit 1
        fi
        KUBECTL="kubectl --kubeconfig=$kubeconfig_file"
        log "Using kubeconfig: $kubeconfig_file"
    else
        KUBECTL="kubectl"
        log "Using current context: $($KUBECTL config current-context)"
    fi
}
