#!/bin/bash

# Deploy Saga Pegasus Stack
# Usage: ./deploy.sh <env> [mode] [inventory_file]
# Supported environments: mainnet, testnet, devnet
# Supported modes: validator (default)

set -e

ENV=${1:-mainnet}
MODE=${2:-validator}
INVENTORY_FILE=${3:-samples/${ENV}-${MODE}.yml.sample}

# Validate environment
if [[ ! "$ENV" =~ ^(mainnet|testnet|devnet)$ ]]; then
    echo "Error: Invalid environment '$ENV'"
    echo "Supported environments: mainnet, testnet, devnet"
    exit 1
fi

# Validate mode
if [[ ! "$MODE" =~ ^(validator)$ ]]; then
    echo "Error: Invalid mode '$MODE'"
    echo "Supported modes: validator"
    exit 1
fi

echo "Deploying Saga Pegasus Stack"
echo "Environment: $ENV"
echo "Mode: $MODE"
echo "Using inventory file: $INVENTORY_FILE"

# Check if inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
    echo "Error: Inventory file $INVENTORY_FILE not found"
    echo "Available inventory files:"
    ls -la samples/
    exit 1
fi

# Check if ansible is available
if ! command -v ansible-playbook &> /dev/null; then
    echo "Error: ansible-playbook is not installed"
    exit 1
fi

# Deploy all components
echo "Starting deployment..."
cd ansible
ansible-playbook -i "../$INVENTORY_FILE" playbooks/deploy.yml

echo "Deployment completed!"
echo ""
echo "You can check the deployment status with:"
echo "kubectl get pods -n sagasrv-spc"
echo "kubectl get pods -n sagasrv-controller"
echo "kubectl get pods -n sagasrv-metrics"
echo ""
echo "View logs with:"
echo "kubectl logs -n sagasrv-spc -l app=spc"
echo "kubectl logs -n sagasrv-controller -l app=controller" 