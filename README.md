# Saga Deploy

This repository contains Ansible playbooks and roles for deploying Saga Pegasus Cluster. The cluster can operate as full node (optionally archive) or validator.

## Prerequisites

- Dedicated Kubernetes cluster. Sharing the cluster with other workloads might be problematic.
- Kubeconfig file with access to the cluster available locally for the deployer. If using RBAC, make sure the Role is allowed to create workloads and Roles.
- Ansible 2.9+
- Python 3.6+
- AWS credentials (for S3 access). A IAM user with S3 permissions need to be created. Once created, share the ARN with us, since it will have to be whitelisted on the genesis bucket.

### Kubernetes Addons
- CSI driver
- A `StorageClass` named `saga-default` handled by the CSI driver and, ideally, persistent. Running ephemeral storages is possible but not advised.
- If `expose_p2p = true`, a LoadBalancer implementation like MetalLB installed in your cluster. Cloud native solutions are also compatible. This is highly recommended, although it is possible not to expose the p2p port publicly and rely on ClusterIP services. The implementation should attach an external ip or hostname to the newly created `LoadBalancer` services. We will typically require 2-3 IPs.

## Deploy Saga Pegasus

### Inventory
Create your inventory file copying one from the `samples` directory, based on the network (e.g.: mainnet) and the mode (e.g.: fullnode). Customize your ansible variables, specifically:
- `network`: staging|testnet|mainnet
- `mode`: `fullnode|service-provider|validator`
- `moniker`: <your_moniker>
- `kubeconfig_file`: local path for the kubeconfig (e.g.: `~/.kube/your_cluster`)
- `expose_p2p`: bool (optional). If true (default, recommended), you will have to be able to allocate external IPs (or hostname) to LoadBalancer services.

Plus, those are the required secrets:
- `aws_access_key_id`: aws credentials to access the S3 genesis bucket. Ask to be whitelisted
- `aws_secret_access_key`: aws credentials to access the S3 genesis bucket.
- `metrics_grafana_password`: password to access the grafana web interface (only if deploying metrics).
- `keychain_password`: password to the local keychain used by the validator (validators only)
- `validator_mnemonic`: only used if `mode = validator`.

RECOMMENDED: use `ansible-vault` to encrypt secrets, keep them in a separate inventory file offline.

### Deploy
Just run
```
cd ansible
ansible-playbook -e @<inventory_file> -e <secrets_file> --vault-password-file <vault_password_file> playbooks/deploy.yml
```

This will install all the roles in the right order: metrics (if enabled), ingress-nginx (if `expose_p2p`), spc and controller. The latter is responsible to spinup all the chainlets once SPC is in sync.

The playbooks are idempotent, so they can be run as much as possible with no negative consequences. It is possible to just redeploy a single component using `--tags <role>`. E.g.: `--tags controller`.

## Migration from AWS
If you are already running a validator on AWS EKS, follow this part to migrate. It is really important to follow the exact sequence of operation to avoid double signing:
1. Deploy the new cluster in fullnode mode. Verify all the chainlets are started and in sync. Check in grafana that the block production doesn't have hiccups.
2. Scale down the old cluster.
3. Redeploy the new cluster in validator mode. It's just a redeploy of the controller and have it redeploy all the chains.


### Deploy the new cluster in fullnode mode
- Make sure `mode: fullnode` in your inventory file.
- Follow the [Deploy Saga Pegasus](#deploy-saga-pegasus) instructions
- Verify that the validator is spinning up new chains once SPC is in sync `kubectl get pods -A | grep chainlet`
- Make sure the chains are in sync: `scripts/chainlets-status.sh [--kubeconfig <kubeconfig_file>]`. It will print a success or failure message at the end.

### Scale down the old cluster
**After making sure the new cluster is in sync**
- Switch context to old EKS cluster (or pass `--kubeconfig <kubeconfig_file>` to the kubectl commands)
- Scale down spc: `kubectl scale deployment spc -n sagasrv-spc --replicas=0`
- `kubectl scale deployment/saga-controller -n sagasrv-controller --replicas=0`
- Print the command to scale down all the chainlets `kubectl get pods -A | awk '/chainlet/{print "kubectl scale deployment/chainlet -n " $1 " --replicas=0"}'`
- Execute the previous command
- Verify all the chainlets are terminated: `kubectl get pods -A | grep chainlet` should be empty

### Redeploy the new cluster in validator mode
**After making sure the old cluster is scaled down completely**

⚠️⚠️⚠️ **WARNING**: Make sure the old cluster is completely scaled down before proceeding. Running two validators simultaneously will result in double signing and slashing. ⚠️⚠️⚠️

- In the inventory set `mode: validator`
- Make sure you have the `validator_mnemonic` correctly set
- Redeploy ([Deploy](#deploy))
- Restart the controller: `kubectl delete pod -l app=controller -n sagasrv-controller`
- Redeploy every chainlet deleting the deployment and having the controller redeploy it as validator: `kubectl get pods -A | awk '/chainlet/{print "kubectl delete deployment chainlet -n " $1}'` and then execute the commands in the output.

Now you should be able to see all the chainlets restarting: `kubectl get pods -A | grep chainlet`. Check the log of any of those to make sure they are participating 