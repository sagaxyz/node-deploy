# Saga Node Deploy

This project provides simplified deployment scripts for running Saga validator nodes, including the Controller component.

## Prerequisites

- Ansible installed
- Kubernetes cluster access (kubectl configured)
- Docker registry access for Saga images

## Environments

The project supports three environments:

- **mainnet** (`spc-1`) - Production environment
- **testnet** (`spc-testnet-2`) - Testing environment  
- **devnet** (`spc-devnet-1`) - Development/Staging environment

## Quick Start

### Deploy Controller Only

```bash
# Deploy Controller for mainnet
./deploy-controller.sh mainnet

# Deploy Controller for testnet
./deploy-controller.sh testnet

# Deploy Controller for devnet
./deploy-controller.sh devnet
```

### Deploy Full Stack

```bash
# Deploy all components (SPC, Controller, Metrics) for mainnet
./deploy.sh mainnet

# Deploy all components for testnet
./deploy.sh testnet

# Deploy all components for devnet
./deploy.sh devnet
```

## Inventory Files

The project includes sample inventory files for each environment:

- `samples/mainnet-controller.yml.sample` - Mainnet Controller deployment
- `samples/testnet-controller.yml.sample` - Testnet Controller deployment
- `samples/devnet-controller.yml.sample` - Devnet Controller deployment
- `samples/mainnet-validator.yml.sample` - Mainnet full stack
- `samples/testnet-validator.yml.sample` - Testnet full stack
- `samples/devnet-validator.yml.sample` - Devnet full stack

## Components

### Controller

The Saga Controller manages chainlets and provides:
- HTTP API on port 19090
- gRPC API on port 18090
- Metrics on port 9000

### SPC (Saga Pegasus Chain)

The main blockchain node component.

### Metrics

Prometheus and Grafana monitoring stack.

## Configuration

### Environment Variables

Each environment has its own configuration in `ansible/group_vars/`:

- `mainnet.yml` - Mainnet configuration
- `testnet.yml` - Testnet configuration  
- `devnet.yml` - Devnet configuration

### Controller Configuration

The Controller can be configured via:

- `controller_image` - Docker image to use
- `controller_namespace` - Kubernetes namespace
- Resource limits and requests
- Port configurations

## Monitoring

After deployment, you can monitor the components:

```bash
# Check pod status
kubectl get pods -n sagasrv-controller
kubectl get pods -n sagasrv-spc
kubectl get pods -n sagasrv-metrics

# View logs
kubectl logs -n sagasrv-controller -l app=controller
kubectl logs -n sagasrv-spc -l app=spc

# Access metrics
kubectl port-forward service/grafana 3000:3000 -n sagasrv-metrics
```

## Troubleshooting

1. **Controller not starting**: Check the logs and ensure the Kubernetes cluster has sufficient resources
2. **Image pull errors**: Verify Docker registry access and image availability
3. **Permission errors**: Ensure the Kubernetes cluster has the necessary RBAC permissions

## Development

To modify the deployment:

1. Edit the templates in `ansible/roles/controller/templates/`
2. Update variables in `ansible/roles/controller/vars/main.yml`
3. Test with a devnet deployment first
4. Apply changes to testnet/mainnet as needed 