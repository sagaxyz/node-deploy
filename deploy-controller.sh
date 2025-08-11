#!/bin/bash

# Deploy Saga Controller
# Usage: ./deploy-controller.sh <env> [inventory_file]
# Supported environments: mainnet, testnet, devnet

set -e

ENV=${1:-mainnet}
INVENTORY_FILE=${2:-samples/${ENV}-controller.yml.sample}

# Validate environment
if [[ ! "$ENV" =~ ^(mainnet|testnet|devnet)$ ]]; then
    echo "Error: Invalid environment '$ENV'"
    echo "Supported environments: mainnet, testnet, devnet"
    exit 1
fi

echo "Deploying Saga Controller for environment: $ENV"
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

# Deploy the controller
echo "Starting Controller deployment..."
cd ansible
ansible-playbook -i "../$INVENTORY_FILE" playbooks/deploy.yml --tags controller

echo "Controller deployment completed!"
echo "You can check the deployment status with:"
echo "kubectl get pods -n sagasrv-controller"
echo "kubectl logs -n sagasrv-controller -l app=controller" 