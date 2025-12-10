#!/bin/sh

# Constants
CONFIG_FILE="/root/.ssc/config/config.toml"

# Optional environment variables (with fallbacks)
GENESIS_URL=${GENESIS_URL:-${GENESIS:-""}}
SNAPSHOT_TRUST_INTERVAL=${SNAPSHOT_TRUST_INTERVAL:-1000}
SYNC_RPC=${SYNC_RPC:-""}
PERSISTENT_PEERS=${PERSISTENT_PEERS:-${PEERS:-""}}

# Validate all required variables
REQUIRED_VARS="CHAIN_ID GENESIS_URL MONIKER"
for VAR in $REQUIRED_VARS; do
  if [ -z "$(eval echo \$$VAR)" ]; then
    echo "Error: Required environment variable $VAR is not set."
    exit 1
  fi
done

# Check if we should start from state sync
ShouldStartFromStateSync() {
  if [ -z "$SYNC_RPC" ]; then
    return 1
  fi
  count=$(echo "$SYNC_RPC" | tr ',' '\n' | wc -l)
  if [ "$count" -ge 2 ]; then
    return 0
  else
    return 1
  fi
}

# Configure state sync
ConfigureStartFromStateSync() {
  echo "Configuring state sync..."
  RPC_SERVER=$(echo "$SYNC_RPC" | awk -F"," '{gsub("tcp","http",$1);print $1}')
  CURRENT_BLOCK=$(curl -s "$RPC_SERVER/status" | jq -r '.result.sync_info.latest_block_height' 2>/dev/null)
  if [ -z "$CURRENT_BLOCK" ] || [ "$CURRENT_BLOCK" = "null" ]; then
    echo "Unable to fetch current block. Skipping state-sync config"
    return
  fi
  echo "Current Block: $CURRENT_BLOCK"
  TRUST_HEIGHT=$((CURRENT_BLOCK - SNAPSHOT_TRUST_INTERVAL))
  if [ "$TRUST_HEIGHT" -lt 0 ]; then
    echo "Not enough blocks to set trust height"
    return
  fi
  echo "Trust Height: $TRUST_HEIGHT"
  TRUST_BLOCK=$(curl -s "$RPC_SERVER/block?height=$TRUST_HEIGHT" 2>/dev/null)
  if [ -z "$TRUST_BLOCK" ] || [ "$TRUST_BLOCK" = "null" ]; then
    echo "Unable to fetch trust block. Skipping state-sync config"
    return
  fi
  TRUST_HASH=$(curl -s "$RPC_SERVER/block?height=$TRUST_HEIGHT" | jq -r '.result.block_id.hash' 2>/dev/null)
  if [ -z "$TRUST_HASH" ] || [ "$TRUST_HASH" = "null" ]; then
    echo "Unable to fetch trust hash. Skipping state-sync config"
    return
  fi
  echo "Trust Hash: $TRUST_HASH"
  echo "Peers: $PERSISTENT_PEERS"
  sed -i -e '/enable =/ s/= .*/= true/' "$CONFIG_FILE"
  sed -i -e "/trust_height =/ s/= .*/= $TRUST_HEIGHT/" "$CONFIG_FILE"
  sed -i -e "/trust_hash =/ s|= .*|= \"$TRUST_HASH\"|" "$CONFIG_FILE"
  sed -i -e "/rpc_servers =/ s^= .*^= \"$SYNC_RPC\"^" "$CONFIG_FILE"
  if [ -n "$PERSISTENT_PEERS" ]; then
    sed -i -e "/seeds =/ s|= .*|= \"$PERSISTENT_PEERS\"|" "$CONFIG_FILE"
  fi
  echo "State sync configured successfully"
}

if [ ! -f "/root/.ssc/config/genesis.json" ]; then
  echo "/root/.ssc/config/genesis.json does not exist. Initializing SSC for the first time..."
  
  if [ -n "$VALIDATOR_MNEMONIC" ]; then
    echo "Initializing validator with mnemonic..."
    echo "$VALIDATOR_MNEMONIC" | sscd init --chain-id "$CHAIN_ID" --recover $MONIKER
  else
    echo "Initializing fullnode..."
    sscd init --chain-id "$CHAIN_ID" $MONIKER
  fi

  if [ -n "$GENESIS_URL" ]; then
    echo "Downloading genesis file from $GENESIS_URL..."
    curl -f "$GENESIS_URL" --output /root/.ssc/config/genesis.json || {
      echo "Failed to download genesis file from $GENESIS_URL"
      exit 1
    }
  fi

  echo "Editing config files"
  if [ -n "$PERSISTENT_PEERS" ]; then
    echo "Setting persistent_peers in config.toml..."
    sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PERSISTENT_PEERS\"|" "$CONFIG_FILE"
  fi

  # Configure state sync if enabled
  if ShouldStartFromStateSync; then
    ConfigureStartFromStateSync
  fi
fi

echo "Starting SSC..."
sscd start $OPTS
