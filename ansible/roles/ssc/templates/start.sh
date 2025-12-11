#!/bin/sh

# Constants
CONFIG_FILE="/root/.ssc/config/config.toml"
APP_FILE="/root/.ssc/config/app.toml"

# Validate all required variables
REQUIRED_VARS="CHAIN_ID GENESIS_URL MONIKER PEERS"

STATESYNC_TRUST_INTERVAL=${STATESYNC_TRUST_INTERVAL:-1000}
SNAPSHOT_INTERVAL=${SNAPSHOT_INTERVAL:-1000}
SNAPSHOT_KEEP_RECENT=${SNAPSHOT_KEEP_RECENT:-2}
PRUNING_STRATEGY=${PRUNING_STRATEGY:-"custom"}
PRUNING_KEEP_RECENT=${PRUNING_KEEP_RECENT:-1000}
PRUNING_INTERVAL=${PRUNING_INTERVAL:-100}

Logger()
{
	MSG=$1
	echo "$(date) $MSG"
}

ValidateEnvVar()
{
  ENVVAR_NAME=$1
  EXITIFUNSET=${2:-1}  # exit if env var is not set. Pass 1 for true, 0 for false i.e. if 0, script will continue executing. Default: True (exit)
  ECHOVAL=${3:-1} # echo the value of the variable in a log entry. Pass 1 = true, 0 = false. Default: True (will echo)

  # Indirect expansion compatible with /bin/sh
  eval "ENVVAR_VALUE=\${$ENVVAR_NAME}"

  if [ -z "$ENVVAR_VALUE" ]; then
    Logger "Environment variable $ENVVAR_NAME is not set"
    if [ "$EXITIFUNSET" -eq 1 ]; then
      Logger "Exiting in error as environment variable $ENVVAR_NAME is not set"
      exit 1
    else
      Logger "Continuing even though environment variable $ENVVAR_NAME is not set"
    fi
  fi
  if [ "$ECHOVAL" -eq 1 ]; then
    Logger "$ENVVAR_NAME: $ENVVAR_VALUE"
  fi
}

ValidateEnvVars() {
  for VAR in $REQUIRED_VARS; do
    ValidateEnvVar $VAR
  done
}

ShouldInit() {
  if [ ! -f "/root/.ssc/config/genesis.json" ]; then
    return 0
  fi
  return 1
}

Init() {
  Logger "Initializing SSC for the first time..."

  sscd init --chain-id "$CHAIN_ID" $MONIKER

  Logger "Downloading genesis file from $GENESIS_URL..."
  curl -f "$GENESIS_URL" --output /root/.ssc/config/genesis.json || {
    Logger "Failed to download genesis file from $GENESIS_URL"
    exit 1
  }
}

EditConfig() {
  Logger "Editing config files"
  if [ -n "$PEERS" ]; then
    Logger "Setting peers in config.toml..."
    sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" "$CONFIG_FILE"
  fi
}

ConfigureStateSync() {
  if [ "$STATESYNC_ENABLED" != "true" ]; then
    Logger "State sync is not enabled. Skipping state-sync config"
    return
  fi

  Logger "Configuring state sync..."
  ValidateEnvVar "STATESYNC_TRUST_INTERVAL"
  ValidateEnvVar "RPC_SERVERS"
  ValidateEnvVar "PEERS"
  RPC_SERVER=$(echo "$RPC_SERVERS" | awk -F"," '{gsub("tcp","http",$1);print $1}')
  CURRENT_BLOCK=$(
    curl -s "$RPC_SERVER/status" \
      | grep -o '"latest_block_height":"[^"]*"' \
      | sed 's/.*:"//;s/"$//'
  )
  if [ -z "$CURRENT_BLOCK" ]; then
    Logger "Unable to fetch current block. Skipping state-sync config"
    return
  fi
  Logger "Current Block: $CURRENT_BLOCK"
  TRUST_HEIGHT=$((CURRENT_BLOCK - STATESYNC_TRUST_INTERVAL))
  if [ "$TRUST_HEIGHT" -lt 0 ]; then
    Logger "Not enough blocks to set trust height"
    return
  fi
  Logger "Trust Height: $TRUST_HEIGHT"
  TRUST_BLOCK=$(curl -s "$RPC_SERVER/block?height=$TRUST_HEIGHT" 2>/dev/null)
  if [ -z "$TRUST_BLOCK" ]; then
    Logger "Unable to fetch trust block. Skipping state-sync config"
    return
  fi
  # Extract trust hash from TRUST_BLOCK using awk (no jq)
  TRUST_HASH=$(
    echo "$TRUST_BLOCK" \
      | awk -F'"hash":"' '{print $2}' \
      | awk -F'"' '{print $1}'
  )
  if [ -z "$TRUST_HASH" ]; then
    Logger "Unable to extract trust hash. Skipping state-sync config"
    return
  fi
  Logger "Trust Hash: $TRUST_HASH"
  Logger "Peers: $PEERS"
  sed -i -e '/enable =/ s/= .*/= true/' "$CONFIG_FILE"
  sed -i -e "/trust_height =/ s/= .*/= $TRUST_HEIGHT/" "$CONFIG_FILE"
  sed -i -e "/trust_hash =/ s|= .*|= \"$TRUST_HASH\"|" "$CONFIG_FILE"
  sed -i -e "/rpc_servers =/ s^= .*^= \"$RPC_SERVERS\"^" "$CONFIG_FILE"
  if [ -n "$PEERS" ]; then
    sed -i -e "/seeds =/ s|= .*|= \"$PEERS\"|" "$CONFIG_FILE"
  fi
  Logger "State sync configured successfully"
}

ConfigureSnapshots() {
  if [ "$SNAPSHOT_ENABLED" = "true" ]; then
    Logger "Setting snapshots..."
    ValidateEnvVar "SNAPSHOT_INTERVAL"
    ValidateEnvVar "SNAPSHOT_KEEP_RECENT"
    sed -i "/snapshot-interval =/ s/= .*/= $SNAPSHOT_INTERVAL/g" "$APP_FILE"
    sed -i "/snapshot-keep-recent =/ s/= .*/= $SNAPSHOT_KEEP_RECENT/g" "$APP_FILE"
  fi
}

Start() {
  Logger "Starting SSC..."
  sscd start $OPTS --pruning "$PRUNING_STRATEGY" --pruning-keep-recent "$PRUNING_KEEP_RECENT" --pruning-interval "$PRUNING_INTERVAL"
}

## Main
ValidateEnvVars
if ShouldInit; then
  Init
fi

EditConfig
ConfigureStateSync
ConfigureSnapshots

Start
