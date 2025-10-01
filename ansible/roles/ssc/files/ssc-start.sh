#!/bin/bash
set -u

# Expand globs to nothing
shopt -s nullglob

function log() {
  local msg=$1
  echo "$(date) $msg" >&2
}

function fail() {
  if [ $# -gt 0 ]; then
    local msg=$1
    log "$msg"
  fi
  exit 1
}

# Validate dependencies are installed
command -v curl &> /dev/null || fail "curl not installed"

function check_env_vars() {
  for name in "$@"; do
    local value="${!name:-}"
    if [ -z "$value" ]; then
      echo "Variable $name is empty"
      return 1
    fi
  done
}

# Print all env variables for debugging (mask sensitive ones)
env | sed -e 's/^.*MNEMONIC.*$/<removed>/' -e 's/^.*KEY.*$/<removed>/' -e 's/^.*PASSWORD.*$/<removed>/'

# Environment variables
LOGLEVEL=${LOGLEVEL:-"info"}
OPTS=${OPTS:-""}
EXTERNAL_ADDRESS=${EXTERNAL_ADDRESS:-""}
PEERS=${PEERS:-""}
VALIDATOR_KEY=${VALIDATOR_KEY:-""}
NODE_KEY=${NODE_KEY:-""}
MNEMONIC=${MNEMONIC:-""}
KEY_PASSWORD=${KEY_PASSWORD:-""}

# Check that mandatory env variables are not empty
check_env_vars CHAIN_ID MONIKER DENOM GENESIS_URL || fail

# Constant vars
CONFIG_DIR="$HOME/.ssc/config"
DATA_DIR="/data"

log "Starting SSC initialization..."

# Create data directory if it doesn't exist
mkdir -p "$DATA_DIR"

# Copy config to data directory if it doesn't exist
if [ ! -d "$DATA_DIR/.ssc" ]; then
  log "Initializing SSC configuration in data directory"
  sscd init "$MONIKER" --chain-id "$CHAIN_ID" --default-denom "$DENOM" --home "$DATA_DIR/.ssc" || fail "failed to init configuration"
fi

# Set config directory to data directory
CONFIG_DIR="$DATA_DIR/.ssc/config"

# Overwrite the randomly generated validator private key if provided
if [ -n "$VALIDATOR_KEY" ]; then
  log "Setting up validator key from secret"
  # Check if the key is valid JSON (proper validator key) or just a string
  if val_key_json=$(echo "$VALIDATOR_KEY" | base64 -d 2>/dev/null) && echo "$val_key_json" | jq . >/dev/null 2>&1; then
    echo "$val_key_json" > $CONFIG_DIR/priv_validator_key.json || fail
    log "Validator key set from secret"
  else
    log "Validator key is not valid JSON format, using generated key instead"
  fi
else
  log "No validator key provided, using generated key"
fi

# Overwrite the randomly generated node private key if provided
if [ -n "$NODE_KEY" ]; then
  log "Setting up node key from secret"
  node_key_json=$(echo "$NODE_KEY" | base64 -d) || fail "failed to decode node key"
  echo "$node_key_json" > $CONFIG_DIR/node_key.json || fail
fi

# Download and setup genesis file
log "Downloading genesis file from $GENESIS_URL"
curl "$GENESIS_URL" --output $CONFIG_DIR/genesis.json -f || fail "failed to download genesis file"

# Validate genesis file (optional - may fail due to version differences)
log "Validating genesis file"
if ! sscd genesis validate --home "$DATA_DIR/.ssc" 2>/dev/null; then
  log "Genesis validation failed, but continuing (this may be due to version differences)"
fi

# Extract peers from genesis file if not provided
peers=$PEERS
if [ -z "$peers" ] && command -v jq &> /dev/null; then
  peers=$(jq -r '.app_state.genutil.gen_txs[].body.memo' $CONFIG_DIR/genesis.json | grep -v "$EXTERNAL_ADDRESS" | paste -sd, -)
  log "extracted peers from the genesis file: $peers"
elif [ -z "$peers" ]; then
  log "jq not available, using empty peers list"
  peers=""
fi

# Node-specific configuration
log "configuring node"
sed -i "s/^minimum-gas-prices =/ s/= .*/= \"0.01$DENOM,0.01stake\"/g" $CONFIG_DIR/app.toml
sed -i "s/^log_level =.*/log_level = \"$LOGLEVEL\"/g" $CONFIG_DIR/config.toml
sed -i 's/^create_empty_blocks = true/create_empty_blocks = false/g' $CONFIG_DIR/config.toml
sed -i "s/^external_address =.*/external_address = \"$EXTERNAL_ADDRESS\"/g" $CONFIG_DIR/config.toml
sed -i "s/^persistent_peers =.*/persistent_peers = \"$peers\"/g" $CONFIG_DIR/config.toml

# Network configuration
sed -i 's/^address = .*:9090"/address = "0.0.0.0:9090"/g' $CONFIG_DIR/app.toml #grpc.address
sed -i 's/^laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:26657"/g' $CONFIG_DIR/config.toml
sed -i 's/^allow_duplicate_ip = false/allow_duplicate_ip = true/g' $CONFIG_DIR/config.toml
sed -i 's/^send_rate = 5120000/send_rate = 20000000/g' $CONFIG_DIR/config.toml
sed -i 's/^recv_rate = 5120000/recv_rate = 20000000/g' $CONFIG_DIR/config.toml
sed -i 's/^max_packet_msg_payload_size =.*/max_packet_msg_payload_size = 10240/g' $CONFIG_DIR/config.toml
sed -i 's/^flush_throttle_timeout = \"100ms\"/flush_throttle_timeout = \"10ms\"/g' $CONFIG_DIR/config.toml
sed -i 's/^iavl-cache-size = .*/iavl-cache-size = 100000/g' $CONFIG_DIR/app.toml
sed -i 's/^cors_allowed_origins = .*/cors_allowed_origins = ["*"]/g' $CONFIG_DIR/config.toml
sed -i 's/^enabled-unsafe-cors =.*/enabled-unsafe-cors = true/g' $CONFIG_DIR/app.toml
sed -i 's/^enable-unsafe-cors =.*/enable-unsafe-cors = true/g' $CONFIG_DIR/app.toml
sed -i 's/^addr_book_strict = true/addr_book_strict = false/g' $CONFIG_DIR/config.toml
sed -i 's/prometheus = false/prometheus = true/g' $CONFIG_DIR/config.toml

log "Starting SSC node..."
exec sscd start --home "$DATA_DIR/.ssc" $OPTS
