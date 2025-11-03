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
- To create loadbalancer services in a cloud native environment you can use the following parameters to configure it:
  - `lb_annotations`: supports a list of any annotations required by your cloud provider
  - `chainlet_external_traffic_policy`: Defaults to `Cluster`, you can set it to `Local` to support a multi-port setup in a single loadbalancer, you will need to consult your cloud provider docuemtnation for compatiblity (for example, for Oracle Cloud, classic LB only supports multi-port configuration with local external traffic).
  - `chainlet_allocate_loadbalancer_node_ports`: Similar to the above, defaults to `false` and can be set to `ture` as needed

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

This will install all the roles in the right order: metrics (if enabled), ingress-nginx (if `expose_p2p`), spc, ssc (if enabled), and controller. The latter is responsible to spinup all the chainlets once SPC is in sync.

### SSC (Saga Security Chain)

The SSC role is optional and controlled by the `ssc.enabled` variable:
- **Enabled by default**: Only for devnet environment
- **Disabled by default**: For mainnet and testnet environments
- **Features**:
  - Downloads genesis file from S3 during initialization
  - Generates validator keys automatically
  - Provides RPC (26657), P2P (26656), gRPC (9090), and metrics (26660) endpoints
  - Uses persistent storage for blockchain data

The playbooks are idempotent, so they can be run as much as possible with no negative consequences. It is possible to just redeploy a single component using `--tags <role>`. E.g.: `--tags controller`.

## Migration from AWS
If you are already running a validator on AWS EKS, follow this part to migrate. It is really important to follow the exact sequence of operation to avoid double signing:
1. Deploy the new cluster in fullnode mode. Verify all the chainlets are started and in sync. Check in grafana that the block production doesn't have hiccups.
2. Scale down the old cluster.
3. Redeploy the new cluster in validator mode. It's just a redeploy of the controller and have it redeploy all the chains.


### Deploy the new cluster in fullnode mode
- Make sure `mode: fullnode` in your inventory file.
- Follow the [Deploy Saga Pegasus](#deploy-saga-pegasus) instructions
- Make sure the chains are in sync: `scripts/cluster.sh chainlets status [--kubeconfig <kubeconfig_file>]`. It will print a success or failure message at the end.

### Scale down the old cluster
**After making sure the new cluster is in sync**
- Switch context to old EKS cluster (or pass `--kubeconfig <kubeconfig_file>` to the kubectl commands)
- Scale down spc: `kubectl scale deployment spc -n sagasrv-spc --replicas=0`
- Scale down controller: `scripts/cluster.sh controller down`
- Scale down chainlets: `kubectl get pods -A | grep chainlet | awk '{print $1}' | xargs -I{} kubectl -n {} scale deployment/chainlet --replicas=0`
- Verify all the chainlets are terminated: `kubectl get pods -A | grep chainlet` should be empty

**If something goes wrong, scale SPC and Controller back up**
- SPC: `kubectl scale deployment spc -n sagasrv-spc --replicas=1`
- Controller: `scripts/cluster.sh controller up`
The controller will scale chainlets back up and the validator will be restored.

### Redeploy the new cluster in validator mode
**After making sure the old cluster is scaled down completely**

⚠️⚠️⚠️ **WARNING**: Make sure the old cluster is completely scaled down before proceeding. Running two validators simultaneously will result in double signing and slashing. ⚠️⚠️⚠️

- In the inventory set `mode: validator`
- Make sure you have the `validator_mnemonic` correctly set
- Wipe out SPC: `kubectl delete deployment spc -n sagasrv-spc && kubectl delete pvc spc-pvc -n sagasrv-spc`
- Redeploy ([Deploy](#deploy))
- Restart the controller: `scripts/cluster.sh controller restart`
- Redeploy every chainlet deleting the deployment and having the controller redeploy it as validator: `scripts/cluster.sh chainlets redeploy` and then execute the commands in the output.

Now you should be able to see all the chainlets restarting: `kubectl get pods -A | grep chainlet`. Check the status with `scripts/cluster.sh chainlets status` making sure all of them are restarting and getting in sync.

## Run a devnet cluster
Devnet cluster is meant for development. It can run a single validator cluster. It is deployed like every other cluster (just `network: devnet`). By default it comes without metrics and does not expose p2p nor other services. For this reasons, transactions will require port-forwarding. E.g.:
- SPC: `kubectl port-forward -n sagasrv-spc service/spc 26657:26657`. Then `spcd --node http://localhost:26657 <your_command>`
- Chainlets: `kubectl port-forward -n saga-<chain_id> service/chainlet 26657:26657`. Then `sagaosd --node http://localhost:26657 <your_command>`

Alternatively, spc and chainlets can be exposed setting `expose_p2p: true`. Also metrics can be deployed setting `metrics_enabled: true`.

### Launch your first chainlet
- Port forward spc: `kubectl port-forward -n sagasrv-spc service/spc 26657:26657`
- Create chainlet stack: `spcd --node http://localhost:26657 tx chainlet create-chainlet-stack SagaOS "SagaOS Chainlet Stack" sagaxyz/sagaos:0.13.1 0.13.1 sha256:ced72e81e44926157e56d1c9dd3c0de5a5af50c2a87380f4be80d9d5196d86d3 100upsaga day 100upsaga --fees 2000upsaga --from saga1nmu5laudnkpcn6jlejrv8dprumqtj00ujl0zk2 -y --chain-id <your_chain_id>`. Just use the "foundation" addres set up and the desired sagaosd version and make sure you set the right chain_id for spc based on your inventory.
- Launch chainlet `spcd --node http://localhost:26657 tx chainlet launch-chainlet saga1nmu5laudnkpcn6jlejrv8dprumqtj00ujl0zk2 SagaOS 0.13.1 myfirstchainlet '{"denom":"gas","gasLimit":10000000,"genAcctBalances":"saga1nmu5laudnkpcn6jlejrv8dprumqtj00ujl0zk2=1000000000","feeAccount":"saga1nmu5laudnkpcn6jlejrv8dprumqtj00ujl0zk2"}' --fees 500000upsaga --gas 800000 --from saga1nmu5laudnkpcn6jlejrv8dprumqtj00ujl0zk2 --yes --chain-id <your_chain_id>`
- (optional) Stop port spc forward process.
- Port forward your chainlet RPC: `kubectl port-forward -n saga-<chain_id> service/chainlet 26657:26657`
- Execute any cosmos transaction using `sagaosd --node http://localhost:26657 <your_command>`.

NOTE: evm transaction will require port forward of port `8545` instead of `26657`.

## Utils
### cluster.sh
Collection of util commands to interact with the cluster. The script is organized into main commands with subcommands for better organization:

#### Controller Commands
- `controller down`               Scale down the controller deployment
- `controller up`                 Scale up the controller deployment  
- `controller restart`            Restart controller pod

#### Individual Chainlet Commands
- `chainlet restart <identifier>`     Restart chainlet pods by namespace or chain_id
- `chainlet redeploy <identifier>`    Redeploy chainlet deployment by namespace or chain_id
- `chainlet wipe <identifier>`        Wipe chainlet data (delete PVC) and redeploy
- `chainlet logs <identifier>`        Follow chainlet logs by namespace or chain_id
- `chainlet status <identifier>`      Show sync status for a specific chainlet
- `chainlet height <identifier>`      Show current block height for a specific chainlet
- `chainlet expand-pvc <identifier> [%]`  Expand chainlet PVC by percentage (default: 20%)

#### Bulk Chainlets Commands
- `chainlets status`              Show status of all chainlets
- `chainlets redeploy`            Redeploy all chainlet deployments in saga-* namespaces

#### Validator Commands
- `validator unjail <identifier>` Unjail validator by namespace or chain_id
- `validator status [<identifier>]` Check validator status on chain(s) - fetches moniker from SPC and checks if validator is in the active set (includes SPC when no identifier specified)

#### Other Commands
- `install-completion`            Install bash completion for cluster.sh

**Usage Examples:**
```bash
# Controller operations
scripts/cluster.sh controller down
scripts/cluster.sh controller restart

# Individual chainlet operations  
scripts/cluster.sh chainlet restart saga-my-chain
scripts/cluster.sh chainlet redeploy saga-my-chain
scripts/cluster.sh chainlet wipe saga-my-chain
scripts/cluster.sh chainlet logs my_chain_id
scripts/cluster.sh chainlet status saga-my-chain
scripts/cluster.sh chainlet height saga-my-chain

# Bulk operations on all chainlets
scripts/cluster.sh chainlets status
scripts/cluster.sh chainlets redeploy

# Validator operations
scripts/cluster.sh validator unjail saga-my-chain
scripts/cluster.sh validator unjail my_chain_id
scripts/cluster.sh validator status saga-my-chain    # Check status on specific chain
scripts/cluster.sh validator status my_chain_id      # Check status using chain_id
scripts/cluster.sh validator status                  # Check status on SPC and all chains
```

Optionally, pass `--kubeconfig <your_kubeconfig>` to use a different context than the current. Use `scripts/cluster.sh --help` or `scripts/cluster.sh COMMAND --help` for detailed usage information.

**Make it faster**
- Add alias `c=<your_path>/scripts/cluster.sh` to the file loaded on start of the terminal (e.g. `~/.bashrc`, `~/.zshrc`)
- Run `c install-completion`
- Enjoy autocomplete of commands, options, namespaces and chainids.

## AlertManager Configuration

AlertManager can be configured with custom notification channels based on alert severity. This is optional and disabled by default.

### Enable AlertManager Configuration
To enable AlertManager configuration, set in your inventory:
```yaml
metrics_alertmanager_config_enabled: true
```

### Notification Channels by Severity
Configure different notification channels for each severity level:

```yaml
metrics_alertmanager_channels:
  critical:
    - name: critical-slack
      type: slack
      api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
      channel: '#alerts-critical'
      title: 'Critical Alert - {{ "{{ .GroupLabels.alertname }}" }}'
      text: '{{ "{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}" }}'
    - name: critical-email
      type: email
      to: ['admin@yourcompany.com']
      subject: 'CRITICAL: {{ "{{ .GroupLabels.alertname }}" }}'

  warning:
    - name: warning-slack
      type: slack
      api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
      channel: '#alerts-warning'
      title: 'Warning Alert - {{ "{{ .GroupLabels.alertname }}" }}'
      text: '{{ "{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}" }}'

  info:
    - name: info-slack
      type: slack
      api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
      channel: '#alerts-info'
      title: 'Info Alert - {{ "{{ .GroupLabels.alertname }}" }}'
      text: '{{ "{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}" }}'
```

### Supported Channel Types
- **Slack**: Requires `api_url`, `channel`, `title`, `text`
- **Email**: Requires `to` (list), `subject`
- **Webhook**: Requires `url`
- **PagerDuty**: Requires `routing_key`, optional `description`

### Global SMTP Configuration
For email notifications, configure SMTP settings:
```yaml
metrics_alertmanager_global:
  smtp_smarthost: 'smtp.yourcompany.com:587'
  smtp_from: 'alertmanager@yourcompany.com'
  smtp_auth_username: 'your-smtp-user'
  smtp_auth_password: 'your-smtp-password'
  smtp_require_tls: true
```

### Custom Routes and Inhibition Rules
Add custom routing rules for specific alerts:
```yaml
metrics_alertmanager_custom_routes:
  - match:
      alertname: ChainletDown
    receiver: critical-alerts
    group_wait: 10s
    repeat_interval: 1h

metrics_alertmanager_inhibit_rules:
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: ['alertname', 'cluster', 'service']
```

### Example Configuration
Here's a complete example for your inventory file:
```yaml
# Disable noisy Kubernetes control plane ServiceMonitors
metrics_kube_proxy_enabled: false
metrics_kube_scheduler_enabled: false
metrics_kube_etcd_enabled: false
metrics_kube_controller_manager_enabled: false

# Enable AlertManager configuration
metrics_alertmanager_config_enabled: true

# SMTP settings for email notifications
metrics_alertmanager_global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'alerts@yourcompany.com'
  smtp_auth_username: 'alerts@yourcompany.com'
  smtp_auth_password: 'your-app-password'
  smtp_require_tls: true

# Notification channels
metrics_alertmanager_channels:
  critical:
    - name: critical-slack
      type: slack
      api_url: 'https://hooks.slack.com/services/<some_secrets>'
      channel: '#alerts-critical'
      title: 'CRITICAL: {{ "{{ .GroupLabels.alertname }}" }}'
      text: '{{ "{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}" }}'
    - name: critical-pagerduty
      type: pagerduty
      routing_key: 'your-pagerduty-integration-key'
      description: 'Critical Saga Alert'

  warning:
    - name: warning-slack
      type: slack
      api_url: 'https://hooks.slack.com/services/<some_secrets>'
      channel: '#alerts-warning'
      title: 'Warning: {{ "{{ .GroupLabels.alertname }}" }}'
      text: '{{ "{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}" }}'
```
