#!/bin/bash

# Source shared logging functions
source "$(dirname "$0")/../shared/log.sh"

print_usage() {
    log "Usage: $0 [OPTIONS]"
    log ""
    log "Check the sync status of SSC and all online chainlets"
    log ""
    log "OPTIONS:"
    log "  --kubeconfig PATH    Path to kubeconfig file (optional)"
    log "  -h, --help          Show this help message"
    log ""
    log "EXAMPLES:"
    log "  $0                                    # Use default kubeconfig"
    log "  $0 --kubeconfig ~/.kube/config       # Use specific kubeconfig"
    log "  $0 --kubeconfig /path/to/config      # Use custom kubeconfig path"
    log ""
    log "DESCRIPTION:"
    log "  This script checks the synchronization status of:"
    log "  - SSC (Saga Staking Chain) node"
    log "  - All online chainlets in the cluster"
    log ""
    log "  Exit codes:"
    log "    0 - All nodes are in sync"
    log "    1 - Some nodes are catching up or not running"
}

# Parse command line arguments
KUBECONFIG_FILE=""
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
        *)
            error "Unknown option: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
done

# Set kubectl command with optional kubeconfig
if [ -n "$KUBECONFIG_FILE" ]; then
    if [ ! -f "$KUBECONFIG_FILE" ]; then
        error "Kubeconfig file not found: $KUBECONFIG_FILE"
        exit 1
    fi
    KUBECTL="kubectl --kubeconfig=$KUBECONFIG_FILE"
    # log "Using kubeconfig: $KUBECONFIG_FILE"
else
    KUBECTL="kubectl"
    # log "Using current context: $($KUBECTL config current-context)"
fi

log ""

ssc_status=$($KUBECTL exec -n sagasrv-ssc deployment/ssc -- sscd status | jq -r '(.SyncInfo // .sync_info) | .catching_up')
case "$ssc_status" in
    "true")
        error "SSC is still catching up"
        exit 1
        ;;
    "false")
        success "SSC is in sync"
        ;;
    *)
        error "Unable to fetch SSC status"
        exit 1
        ;;
esac

chainlets=$($KUBECTL exec -n sagasrv-ssc deployment/ssc -- sscd q chainlet list-chainlets --limit 1000 --output json | jq -r '.Chainlets[] | select(.status == "STATUS_ONLINE") | .chainId')
if [ -z "$chainlets" ]; then
    error "No chainlets found"
    exit 1
fi

tmp_dir=$(mktemp -d)
log "Loading chainlets status..."
pids=()
for chainlet in $chainlets; do
    namespace="saga-${chainlet//_/-}"
    output_file="$tmp_dir/$namespace.txt"
    $KUBECTL exec -n $namespace deployment/chainlet -- sagaosd status 2>/dev/null | tee "$output_file" >/dev/null &
    pids+=($!)
done

# Wait for all background processes to complete
for pid in "${pids[@]}"; do
    wait $pid
done

# Initialize counters
in_sync=0
catching_up=0
not_running=0
catching_up_chains=()
not_running_chains=()

# Check status for each chainlet
for file in "$tmp_dir"/*.txt; do
    if [ -f "$file" ]; then
        # Extract chainlet name from filename
        chainlet=$(basename "$file" .txt | sed 's/saga-//')
        
        # Extract status from file
        status=$(cat "$file" | jq -r '(.SyncInfo // .sync_info) | .catching_up' 2>/dev/null)
        
        case "$status" in
            "false")
                ((in_sync++))
                ;;
            "true")
                ((catching_up++))
                catching_up_chains+=("saga-${chainlet//_/-}")
                ;;
            *)
                ((not_running++))
                not_running_chains+=("saga-${chainlet//_/-}")
                ;;
        esac
    fi
done

# Cleanup temp directory
rm -rf "$tmp_dir"

log ""
log "======== Status Summary ========"
log "🟢 In sync: $in_sync"
log "🟡 Catching up: $catching_up"
if [ ${#catching_up_chains[@]} -gt 0 ]; then
    log "${catching_up_chains[*]}"
fi
log "🔴 Not running: $not_running"
if [ ${#not_running_chains[@]} -gt 0 ]; then
    log "${not_running_chains[*]}"
fi

log ""

# Print final status
total=$((in_sync + catching_up + not_running))
if [ $in_sync -eq $total ]; then
    success "✅ All $total chainlets in sync"
    exit 0
else
    error "❌ $in_sync in sync, $catching_up catching up, $not_running not running (of $total total)"
    exit 1
fi
