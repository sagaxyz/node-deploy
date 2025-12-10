#!/bin/sh

# Constants
CONFIG_FILE="/root/.ssc/config/config.toml"

# Optional environment variables
SNAPSHOT_TRUST_INTERVAL=${SNAPSHOT_TRUST_INTERVAL:-1000}

# Validate all required variables
REQUIRED_VARS="CHAIN_ID GENESIS MONIKER"
for VAR in $REQUIRED_VARS; do
  if [ -z "$(eval echo \$$VAR)" ]; then
    echo "Error: Required environment variable $VAR is not set."
    exit 1
  fi
done

# Log CHAIN_ID
echo "CHAIN_ID: $CHAIN_ID"

# Check if we should start from state sync
ShouldStartFromStateSync() {
  if [ "${STATE_SYNC_ENABLED:-false}" != "true" ]; then
    return 1
  fi
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
  
  # Fetch current block using grep/sed (jq not available)
  CURRENT_BLOCK=$(
    curl -s "$RPC_SERVER/status" \
      | grep -o '"latest_block_height":"[^"]*"' \
      | sed 's/.*:"//;s/"$//'
  )
  if [ -z "$CURRENT_BLOCK" ]; then
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
  if [ -z "$TRUST_BLOCK" ]; then
    echo "Unable to fetch trust block. Skipping state-sync config"
    return
  fi
  # Extract trust hash from TRUST_BLOCK using awk (no jq)
  TRUST_HASH=$(
    echo "$TRUST_BLOCK" \
      | awk -F'"hash":"' '{print $2}' \
      | awk -F'"' '{print $1}'
  )
  if [ -z "$TRUST_HASH" ]; then
    echo "Unable to extract trust hash. Skipping state-sync config"
    return
  fi
  echo "Trust Hash: $TRUST_HASH"
  echo "Peers: $PEERS"
  sed -i -e '/enable =/ s/= .*/= true/' "$CONFIG_FILE"
  sed -i -e "/trust_height =/ s/= .*/= $TRUST_HEIGHT/" "$CONFIG_FILE"
  sed -i -e "/trust_hash =/ s|= .*|= \"$TRUST_HASH\"|" "$CONFIG_FILE"
  sed -i -e "/rpc_servers =/ s^= .*^= \"$SYNC_RPC\"^" "$CONFIG_FILE"
  if [ -n "$PEERS" ]; then
    sed -i -e "/seeds =/ s|= .*|= \"$PEERS\"|" "$CONFIG_FILE"
  fi
  echo "State sync configured successfully"
}

# Ensure config directory exists
mkdir -p /root/.ssc/config

# Clean up any stale database lock files from previous crashes
echo "Cleaning up stale database lock files..."
find /root/.ssc/data -name "LOCK" -type f -delete 2>/dev/null || true
find /root/.ssc/data -name "*.lock" -type f -delete 2>/dev/null || true
find /root/.ssc -name "LOCK" -type f -delete 2>/dev/null || true
find /root/.ssc -name "*.lock" -type f -delete 2>/dev/null || true
echo "Database lock cleanup complete"

if [ ! -f "/root/.ssc/config/genesis.json" ]; then
  echo "/root/.ssc/config/genesis.json does not exist. Initializing SSC for the first time..."
  
  if [ -n "$VALIDATOR_MNEMONIC" ]; then
    echo "Initializing validator with mnemonic..."
    echo "$VALIDATOR_MNEMONIC" | sscd init --chain-id "$CHAIN_ID" --recover $MONIKER
  else
    echo "Initializing fullnode..."
    sscd init --chain-id "$CHAIN_ID" $MONIKER
  fi

  if [ -n "$GENESIS" ]; then
    echo "Downloading genesis file from $GENESIS..."
    curl -f "$GENESIS" --output /root/.ssc/config/genesis.json || {
      echo "Failed to download genesis file from $GENESIS"
      exit 1
    }
    
    # Fix invalid IBC channel parameters if upgrade_timeout_timestamp is 0
    echo "=== IBC Parameter Fix ==="
      
      # Calculate future timestamp (1 year from now in nanoseconds)
      FUTURE_TIMESTAMP_SEC=$(date -d "+1 year" +%s 2>/dev/null || date -v+1y +%s 2>/dev/null || echo "0")
      if [ "$FUTURE_TIMESTAMP_SEC" = "0" ]; then
        # Fallback: use a fixed future date (Jan 1, 2026)
        FUTURE_TIMESTAMP_SEC=1735689600
        echo "Using fallback timestamp: $FUTURE_TIMESTAMP_SEC"
      fi
      FUTURE_TIMESTAMP_NS=$((FUTURE_TIMESTAMP_SEC * 1000000000))
      echo "Future timestamp (nanoseconds): $FUTURE_TIMESTAMP_NS"
      
    # Fix upgrade_timeout_timestamp using sed (no jq required)
    echo "Attempting to fix IBC upgrade_timeout_timestamp..."
      
    # Check if upgrade_timeout_timestamp exists and is 0 or null, then fix it
    # Pattern: "upgrade_timeout_timestamp": 0 or "upgrade_timeout_timestamp": null
    if grep -q '"upgrade_timeout_timestamp"[[:space:]]*:[[:space:]]*\(0\|null\)' /root/.ssc/config/genesis.json 2>/dev/null; then
      echo "Found invalid upgrade_timeout_timestamp (0 or null), fixing..."
      sed -i 's/"upgrade_timeout_timestamp"[[:space:]]*:[[:space:]]*\(0\|null\)/"upgrade_timeout_timestamp": '"$FUTURE_TIMESTAMP_NS"'/g' /root/.ssc/config/genesis.json
      echo "Fixed upgrade_timeout_timestamp"
    else
      # If the field doesn't exist, try to add it in the params section
      # Look for "params": { and add the field after it
      if ! grep -q '"upgrade_timeout_timestamp"' /root/.ssc/config/genesis.json 2>/dev/null; then
        echo "upgrade_timeout_timestamp not found, attempting to add it..."
        # Try to add after "params": { in the channel_genesis section
        sed -i '/"channel_genesis"[^}]*"params"[[:space:]]*:[[:space:]]*{/a\
    "upgrade_timeout_timestamp": '"$FUTURE_TIMESTAMP_NS"',' /root/.ssc/config/genesis.json 2>/dev/null || echo "Could not automatically add upgrade_timeout_timestamp"
      else
        echo "upgrade_timeout_timestamp already exists with valid value"
      fi
    fi
      
      # Fix IBC transfer module genesis compatibility (remove denom_traces for IBC-go v10)
      echo "Fixing IBC transfer module genesis compatibility..."
    if grep -q '"denom_traces"' /root/.ssc/config/genesis.json 2>/dev/null; then
        echo "Removing deprecated 'denom_traces' field from IBC transfer genesis..."
      # Remove the line containing denom_traces
      sed -i '/"denom_traces"/d' /root/.ssc/config/genesis.json
      # Fix any trailing commas before closing braces/brackets on the same line
      sed -i 's/,[[:space:]]*}/}/g' /root/.ssc/config/genesis.json
      sed -i 's/,[[:space:]]*]/]/g' /root/.ssc/config/genesis.json
      # Fix trailing commas on previous line before closing brace
      sed -i -e ':a' -e 'N' -e '$!ba' -e 's/,[[:space:]]*\n[[:space:]]*}/}\n/g' /root/.ssc/config/genesis.json
        echo "Removed denom_traces field"
      else
        echo "No denom_traces field found (already compatible or not present)"
      fi
    
    # Fix IBC core module genesis compatibility (remove params field for IBC-go v10)
    echo "Fixing IBC core module genesis compatibility..."
    # Check if params field exists in the ibc section (not in transfer or other modules)
    if grep -q '"ibc"' /root/.ssc/config/genesis.json 2>/dev/null; then
      # Use Python if available, otherwise use awk
      if command -v python3 >/dev/null 2>&1; then
        echo "Using Python to remove params field from IBC core genesis..."
        python3 << 'PYTHON_SCRIPT'
import json
import sys

try:
    # Read the original file to preserve formatting as much as possible
    with open('/root/.ssc/config/genesis.json', 'r') as f:
        content = f.read()
        genesis = json.loads(content)
    
    # Remove params from ibc section if it exists
    removed = False
    if 'app_state' in genesis and isinstance(genesis['app_state'], dict):
        if 'ibc' in genesis['app_state'] and isinstance(genesis['app_state']['ibc'], dict):
            if 'params' in genesis['app_state']['ibc']:
                del genesis['app_state']['ibc']['params']
                removed = True
                print("Removed params field from IBC core genesis")
    
    if removed:
        # Write back the modified genesis with consistent formatting
        with open('/root/.ssc/config/genesis.json', 'w') as f:
            json.dump(genesis, f, indent=2, separators=(',', ': '))
    else:
        print("No params field found in IBC core genesis (already compatible)")
except json.JSONDecodeError as e:
    print(f"Error: Invalid JSON in genesis file: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Error processing genesis file: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
      else
        echo "Python not available, using awk to remove params field from IBC core genesis..."
        # Use awk as fallback - remove params field and its object value
        awk '
        BEGIN { 
          in_ibc = 0
          in_params = 0
          params_depth = 0
        }
        /"ibc"[[:space:]]*:[[:space:]]*{/ { 
          in_ibc = 1
          print
          next
        }
        in_ibc && /[[:space:]]*"params"[[:space:]]*:[[:space:]]*{/ {
          in_params = 1
          params_depth = 1
          next
        }
        in_params {
          # Count braces to know when params block ends
          gsub(/{/, "&")
          open_count = gsub(/{/, "")
          gsub(/}/, "&")
          close_count = gsub(/}/, "")
          params_depth += open_count - close_count
          if (params_depth <= 0) {
            in_params = 0
          }
          next
        }
        in_ibc && /^[[:space:]]*}/ {
          in_ibc = 0
        }
        { print }
        ' /root/.ssc/config/genesis.json > /root/.ssc/config/genesis.json.tmp && \
          mv /root/.ssc/config/genesis.json.tmp /root/.ssc/config/genesis.json
        
        # Fix any trailing commas that might be left after removing params
        sed -i 's/,[[:space:]]*}/}/g' /root/.ssc/config/genesis.json
        sed -i 's/,[[:space:]]*]/]/g' /root/.ssc/config/genesis.json
        sed -i -e ':a' -e 'N' -e '$!ba' -e 's/,[[:space:]]*\n[[:space:]]*}/}\n/g' /root/.ssc/config/genesis.json
        echo "Removed params field from IBC core genesis (using awk)"
      fi
    else
      echo "No IBC section found in genesis file"
    fi
    
    echo "=== IBC Parameter Fix Complete ==="
  else
    echo "Error: GENESIS is required but not set"
    exit 1
  fi

  echo "Editing config files"
  if [ -n "$PEERS" ]; then
    echo "Setting persistent_peers in config.toml..."
    sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" "$CONFIG_FILE"
  fi

  # Configure snapshot interval if provided
  if [ -n "$SNAPSHOT_INTERVAL" ]; then
    echo "Setting snapshot-interval in app.toml..."
    sed -i "s|^snapshot-interval *=.*|snapshot-interval = $SNAPSHOT_INTERVAL|" /root/.ssc/config/app.toml
  fi

  # Configure state sync if enabled (only during initial setup when genesis doesn't exist)
  if ShouldStartFromStateSync; then
    ConfigureStartFromStateSync
  fi
fi

# Verify genesis file exists before starting
if [ ! -f "/root/.ssc/config/genesis.json" ]; then
  echo "Error: genesis.json file does not exist at /root/.ssc/config/genesis.json"
  echo "Cannot start SSC without genesis file"
  exit 1
fi

# Apply IBC compatibility fixes to existing genesis file (runs every time)
echo "=== Applying IBC Compatibility Fixes ==="

# Calculate future timestamp (1 year from now in nanoseconds)
FUTURE_TIMESTAMP_SEC=$(date -d "+1 year" +%s 2>/dev/null || date -v+1y +%s 2>/dev/null || echo "0")
if [ "$FUTURE_TIMESTAMP_SEC" = "0" ]; then
  # Fallback: use a fixed future date (Jan 1, 2026)
  FUTURE_TIMESTAMP_SEC=1735689600
  echo "Using fallback timestamp: $FUTURE_TIMESTAMP_SEC"
fi
FUTURE_TIMESTAMP_NS=$((FUTURE_TIMESTAMP_SEC * 1000000000))
echo "Future timestamp (nanoseconds): $FUTURE_TIMESTAMP_NS"

# Fix upgrade_timeout_timestamp if needed
if grep -q '"upgrade_timeout_timestamp"[[:space:]]*:[[:space:]]*\(0\|null\)' /root/.ssc/config/genesis.json 2>/dev/null; then
  echo "Found invalid upgrade_timeout_timestamp (0 or null), fixing..."
  sed -i 's/"upgrade_timeout_timestamp"[[:space:]]*:[[:space:]]*\(0\|null\)/"upgrade_timeout_timestamp": '"$FUTURE_TIMESTAMP_NS"'/g' /root/.ssc/config/genesis.json
  echo "Fixed upgrade_timeout_timestamp"
fi

# Fix IBC transfer module genesis compatibility (remove denom_traces for IBC-go v10)
if grep -q '"denom_traces"' /root/.ssc/config/genesis.json 2>/dev/null; then
  echo "Removing deprecated 'denom_traces' field from IBC transfer genesis..."
  sed -i '/"denom_traces"/d' /root/.ssc/config/genesis.json
  # Fix any trailing commas before closing braces/brackets on the same line
  sed -i 's/,[[:space:]]*}/}/g' /root/.ssc/config/genesis.json
  sed -i 's/,[[:space:]]*]/]/g' /root/.ssc/config/genesis.json
  # Fix trailing commas on previous line before closing brace
  sed -i -e ':a' -e 'N' -e '$!ba' -e 's/,[[:space:]]*\n[[:space:]]*}/}\n/g' /root/.ssc/config/genesis.json
  echo "Removed denom_traces field"
fi

# Fix IBC core module genesis compatibility (remove params field for IBC-go v10)
echo "Fixing IBC core module genesis compatibility..."
if grep -q '"ibc"' /root/.ssc/config/genesis.json 2>/dev/null; then
  # Use Python if available, otherwise use awk
  if command -v python3 >/dev/null 2>&1; then
    echo "Using Python to remove params field from IBC core genesis..."
    python3 << 'PYTHON_SCRIPT'
import json
import sys

try:
    # Read the original file
    with open('/root/.ssc/config/genesis.json', 'r') as f:
        genesis = json.load(f)
    
    # Remove params from ibc section if it exists
    removed = False
    if 'app_state' in genesis and isinstance(genesis['app_state'], dict):
        if 'ibc' in genesis['app_state'] and isinstance(genesis['app_state']['ibc'], dict):
            if 'params' in genesis['app_state']['ibc']:
                print(f"Found params field in IBC core genesis, removing...")
                del genesis['app_state']['ibc']['params']
                removed = True
                print("Successfully removed params field from IBC core genesis")
            else:
                print("No params field found in IBC core genesis (already compatible)")
        else:
            print("No 'ibc' key found in app_state")
    else:
        print("No 'app_state' key found in genesis")
    
    if removed:
        # Write back the modified genesis with consistent formatting
        with open('/root/.ssc/config/genesis.json', 'w') as f:
            json.dump(genesis, f, indent=2, separators=(',', ': '))
        print("Genesis file updated successfully")
except json.JSONDecodeError as e:
    print(f"Error: Invalid JSON in genesis file: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Error processing genesis file: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_SCRIPT
    PYTHON_EXIT=$?
    if [ $PYTHON_EXIT -ne 0 ]; then
      echo "Python script failed, falling back to awk method..."
    else
      echo "Python fix completed successfully"
    fi
  fi
  
  # Use awk if Python failed or is not available
  if ! command -v python3 >/dev/null 2>&1 || [ "${PYTHON_EXIT:-1}" -ne 0 ]; then
    echo "Using awk to remove params field from IBC core genesis..."
    # Use awk as fallback - remove params field and its object value
    awk '
    BEGIN { 
      in_ibc = 0
      in_params = 0
      params_depth = 0
    }
    /"ibc"[[:space:]]*:[[:space:]]*{/ { 
      in_ibc = 1
      print
      next
    }
    in_ibc && /[[:space:]]*"params"[[:space:]]*:[[:space:]]*{/ {
      in_params = 1
      params_depth = 1
      next
    }
    in_params {
      # Count braces to know when params block ends
      gsub(/{/, "&")
      open_count = gsub(/{/, "")
      gsub(/}/, "&")
      close_count = gsub(/}/, "")
      params_depth += open_count - close_count
      if (params_depth <= 0) {
        in_params = 0
      }
      next
    }
    in_ibc && /^[[:space:]]*}/ {
      in_ibc = 0
    }
    { print }
    ' /root/.ssc/config/genesis.json > /root/.ssc/config/genesis.json.tmp && \
      mv /root/.ssc/config/genesis.json.tmp /root/.ssc/config/genesis.json
    
    # Fix any trailing commas that might be left after removing params
    sed -i 's/,[[:space:]]*}/}/g' /root/.ssc/config/genesis.json
    sed -i 's/,[[:space:]]*]/]/g' /root/.ssc/config/genesis.json
    sed -i -e ':a' -e 'N' -e '$!ba' -e 's/,[[:space:]]*\n[[:space:]]*}/}\n/g' /root/.ssc/config/genesis.json
    echo "Removed params field from IBC core genesis (using awk)"
  fi
else
  echo "No IBC section found in genesis file"
fi

echo "=== IBC Compatibility Fixes Complete ==="

# Final cleanup of any lock files before starting
echo "Final cleanup of database lock files before starting..."
find /root/.ssc/data -name "LOCK" -type f -delete 2>/dev/null || true
find /root/.ssc/data -name "*.lock" -type f -delete 2>/dev/null || true
find /root/.ssc -name "LOCK" -type f -delete 2>/dev/null || true
find /root/.ssc -name "*.lock" -type f -delete 2>/dev/null || true

# Ensure data directory exists
mkdir -p /root/.ssc/data

echo "Starting SSC..."
sscd start $OPTS
