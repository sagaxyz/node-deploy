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
    log "  status [<identifier>]          Check validator status on chain(s)"
    log ""
    log "EXAMPLES:"
    log "  cluster.sh validator unjail saga-my-chain          # Unjail using full namespace"
    log "  cluster.sh validator unjail my_chain_id            # Unjail using chain_id (converts to saga-my-chain-id)"
    log "  cluster.sh validator status saga-my-chain          # Check validator status on specific chain"
    log "  cluster.sh validator status my_chain_id            # Check validator status using chain_id"
    log "  cluster.sh validator status                        # Check validator status on SPC and all chains"
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

validator_status_single() {
    local namespace="$1"
    local chain_id="${namespace#saga-}"
    chain_id="${chain_id//-/_}"

    # Get moniker from SPC deployment
    local moniker=$($KUBECTL get deployment spc -n sagasrv-spc -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MONIKER")].value}' 2>/dev/null)

    if [ -z "$moniker" ]; then
        error "Could not fetch moniker from SPC deployment"
        return 1
    fi

    # Query validators in the chainlet
    local validators_output=$($KUBECTL exec deployment/chainlet -n "$namespace" -- sagaosd q staking validators --output json 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$validators_output" ]; then
        error "Failed to query validators in namespace '$namespace'"
        return 1
    fi

    # Check if our validator is in the set
    local validator_info=$(echo "$validators_output" | jq -r --arg moniker "$moniker" '.validators[] | select(.description.moniker == $moniker)')

    if [ -n "$validator_info" ]; then
        local status=$(echo "$validator_info" | jq -r '.status')
        local jailed=$(echo "$validator_info" | jq -r '.jailed')

        # Format status message
        local status_msg=""
        case "$status" in
            "BOND_STATUS_BONDED")
                status_msg="Active (Bonded)"
                ;;
            "BOND_STATUS_UNBONDING")
                status_msg="Unbonding"
                ;;
            "BOND_STATUS_UNBONDED")
                status_msg="Unbonded"
                ;;
            *)
                status_msg="$status"
                ;;
        esac

        if [ "$jailed" = "true" ]; then
            status_msg="$status_msg, Jailed"
            echo -e "\033[31m[SUCCESS] [$chain_id] Validator '$moniker' is in the validator set - Status: $status_msg\033[0m"
        else
            success "[$chain_id] Validator '$moniker' is in the validator set - Status: $status_msg"
        fi
    else
        warning "[$chain_id] Validator '$moniker' is NOT in the validator set"
    fi
}

validator_status_spc() {
    # Get moniker from SPC deployment
    local moniker=$($KUBECTL get deployment spc -n sagasrv-spc -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MONIKER")].value}' 2>/dev/null)

    if [ -z "$moniker" ]; then
        error "Could not fetch moniker from SPC deployment"
        return 1
    fi

    # Query validators in SPC
    local validators_output=$($KUBECTL exec deployment/spc -n sagasrv-spc -- spcd q staking validators --output json 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$validators_output" ]; then
        error "Failed to query validators in SPC"
        return 1
    fi

    # Check if our validator is in the set
    local validator_info=$(echo "$validators_output" | jq -r --arg moniker "$moniker" '.validators[] | select(.description.moniker == $moniker)')

    if [ -n "$validator_info" ]; then
        local status=$(echo "$validator_info" | jq -r '.status')
        local jailed=$(echo "$validator_info" | jq -r '.jailed')

        # Format status message
        local status_msg=""
        case "$status" in
            "BOND_STATUS_BONDED")
                status_msg="Active (Bonded)"
                ;;
            "BOND_STATUS_UNBONDING")
                status_msg="Unbonding"
                ;;
            "BOND_STATUS_UNBONDED")
                status_msg="Unbonded"
                ;;
            *)
                status_msg="$status"
                ;;
        esac

        if [ "$jailed" = "true" ]; then
            status_msg="$status_msg, Jailed"
            echo -e "\033[31m[SUCCESS] [SPC] Validator '$moniker' is in the validator set - Status: $status_msg\033[0m"
        else
            success "[SPC] Validator '$moniker' is in the validator set - Status: $status_msg"
        fi
    else
        warning "[SPC] Validator '$moniker' is NOT in the validator set"
    fi
}

validator_status() {
    local identifier="$1"
    if [ -n "$identifier" ]; then
        # Check status for specific chain
        local namespace=$(get_namespace "$identifier")
        log "Checking validator status in namespace: $namespace"
        validator_status_single "$namespace"
    else
        # Check status for all chains including SPC
        log "Checking validator status on SPC and all chains..."
        # Create temporary directory for parallel processing
        local tmp_dir=$(mktemp -d)
        local pids=()
        # Start SPC status check in parallel
        local spc_output_file="$tmp_dir/spc.txt"
        (
            validator_status_spc > "$spc_output_file" 2>&1
            echo $? > "$spc_output_file.exit"
        ) &
        pids+=($!)
        # Get list of online chainlets from SPC
        local chainlets=$($KUBECTL exec -n sagasrv-spc deployment/spc -- spcd q chainlet list-chainlets --limit 1000 --output json 2>/dev/null | jq -r '.Chainlets[] | select(.status == "STATUS_ONLINE") | .chainId')
        if [ -n "$chainlets" ]; then
            # Start parallel status checks for chainlets
            for chainlet in $chainlets; do
                local namespace="saga-${chainlet//_/-}"
                local output_file="$tmp_dir/$namespace.txt"
                (
                    validator_status_single "$namespace" > "$output_file" 2>&1
                    echo $? > "$output_file.exit"
                ) &
                pids+=($!)
            done
        else
            warning "No online chainlets found"
        fi
        # Wait for all background processes to complete
        for pid in "${pids[@]}"; do
            wait $pid
        done
        # Display results (SPC first, then chainlets)
        if [ -f "$spc_output_file" ]; then
            cat "$spc_output_file"
        fi
        for file in "$tmp_dir"/*.txt; do
            if [ -f "$file" ] && [ ! "${file%.exit}" != "$file" ] && [ "$file" != "$spc_output_file" ]; then
                cat "$file"
            fi
        done
        # Clean up
        rm -rf "$tmp_dir"
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
        status)
            validator_status "$1"
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
