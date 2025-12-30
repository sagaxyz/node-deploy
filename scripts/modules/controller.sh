#!/bin/bash

# Controller management module

# Source shared utilities
source "$(dirname "${BASH_SOURCE[0]}")/shared.sh"

controller_print_usage() {
    log "Usage: cluster.sh controller SUBCOMMAND"
    log ""
    log "Controller management commands"
    log ""
    log "SUBCOMMANDS:"
    log "  down      Scale down the controller deployment"
    log "  up        Scale up the controller deployment"
    log "  restart   Restart controller pod"
    log "  logs      Follow controller logs"
    log ""
    log "EXAMPLES:"
    log "  cluster.sh controller down"
    log "  cluster.sh controller up"
    log "  cluster.sh controller restart"
    log "  cluster.sh controller logs"
}

controller_scale_down() {
    log "Scaling down controller..."
    log_and_execute_cmd $KUBECTL scale deployment/controller -n sagasrv-controller --replicas=0
    if [ $? -eq 0 ]; then
        success "Controller scaled down successfully. Don't forget to run 'cluster.sh controller up'"
    else
        error "Failed to scale down controller"
        exit 1
    fi
}

controller_scale_up() {
    log "Scaling up controller..."
    log_and_execute_cmd $KUBECTL scale deployment/controller -n sagasrv-controller --replicas=1
    if [ $? -eq 0 ]; then
        success "Controller scaled up successfully"
    else
        error "Failed to scale up controller"
        exit 1
    fi
}

controller_restart() {
    log "Restarting controller..."
    log_and_execute_cmd $KUBECTL delete pod -n sagasrv-controller -l app=controller

    if [ $? -eq 0 ]; then
        success "Controller pod restarted successfully"
        log "New pod will be created automatically by the deployment"
    else
        error "Failed to restart controller pod"
        exit 1
    fi
}

controller_logs() {
    log "Following logs for controller in namespace: sagasrv-controller"
    # Follow logs with exec (replaces current process)
    exec $KUBECTL logs -f deployment/controller -n sagasrv-controller
}

# Main controller command handler
handle_controller_command() {
    local subcommand="$1"
    
    case "$subcommand" in
        down)
            controller_scale_down
            ;;
        up)
            controller_scale_up
            ;;
        restart)
            controller_restart
            ;;
        logs)
            controller_logs
            ;;
        -h|--help|help|"")
            controller_print_usage
            ;;
        *)
            error "Unknown controller subcommand: $subcommand"
            echo ""
            controller_print_usage
            exit 1
            ;;
    esac
}
