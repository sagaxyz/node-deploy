#!/bin/bash

# Validator management module

# Source shared utilities
source "$(dirname "${BASH_SOURCE[0]}")/shared.sh"

validator_print_usage() {
    log "Usage: cluster.sh validator SUBCOMMAND [OPTIONS]"
    log ""
    log "Validator management commands"
    log ""
    log "SUBCOMMANDS:"
    log "  unjail <identifier>            Unjail validator by namespace or chain_id"
    log ""
    log "EXAMPLES:"
    log "  cluster.sh validator unjail saga-my-chain          # Unjail using full namespace"
    log "  cluster.sh validator unjail my_chain_id            # Unjail using chain_id (converts to saga-my-chain-id)"
}

validator_unjail() {
    local identifier="$1"
    if [ -z "$identifier" ]; then
        error "unjail command requires an identifier (namespace or chain_id)"
        echo ""
        validator_print_usage
        exit 1
    fi
    
    local namespace=$(get_namespace "$identifier")
    log "Unjailing validator in namespace: $namespace"

    log_and_execute_cmd $KUBECTL exec deployment/chainlet -n "$namespace" -- bash -c \''echo $KEYPASSWD | sagaosd tx slashing unjail --fees 2000stake -y --from chainlet-operator-key'\'

    if [ $? -eq 0 ]; then
        success "Validator in namespace '$namespace' unjailed successfully"
    else
        error "Failed to unjail validator in namespace '$namespace'"
        exit 1
    fi
}

# Main validator command handler
handle_validator_command() {
    local subcommand="$1"
    shift  # Remove subcommand from arguments
    
    case "$subcommand" in
        unjail)
            validator_unjail "$1"
            ;;
        -h|--help|help|"")
            validator_print_usage
            ;;
        *)
            error "Unknown validator subcommand: $subcommand"
            echo ""
            validator_print_usage
            exit 1
            ;;
    esac
}
