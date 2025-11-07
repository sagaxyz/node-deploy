#!/bin/sh

# Constants
CONFIG_FILE="/root/.ssc/config/config.toml"

# Validate all required variables
REQUIRED_VARS="CHAIN_ID GENESIS_URL MONIKER"
for VAR in $REQUIRED_VARS; do
  if [ -z "$(eval echo \$$VAR)" ]; then
    echo "Error: Required environment variable $VAR is not set."
    exit 1
  fi
done

if [ ! -f "/root/.ssc/config/genesis.json" ]; then
  echo "/root/.ssc/config/genesis.json does not exist. Initializing SSC for the first time..."
  
  if [ -n "$VALIDATOR_MNEMONIC" ]; then
    echo "Initializing validator with mnemonic..."
    echo "$VALIDATOR_MNEMONIC" | sscd init --chain-id "$CHAIN_ID" --recover $MONIKER
  else
    echo "Initializing fullnode..."
    sscd init --chain-id "$CHAIN_ID" $MONIKER
  fi

  echo "Downloading genesis file from $GENESIS_URL..."
  curl -f "$GENESIS_URL" --output /root/.ssc/config/genesis.json || {
    echo "Failed to download genesis file from $GENESIS_URL"
    exit 1
  }

  echo "Editing config files"
  if [ -n "$PERSISTENT_PEERS" ]; then
    echo "Setting persistent_peers in config.toml..."
    sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PERSISTENT_PEERS\"|" "$CONFIG_FILE"
  fi
fi

echo "Starting SSC..."
sscd start $OPTS
