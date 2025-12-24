#!/usr/bin/env bash
set -euo pipefail



export WG_CONF_B64=$(echo "$WG_CONF" | base64 -w 0)

# Dashboard & Verification Settings
# We'll skip deSEC and other integrations by setting them empty
export DESEC_DOMAIN=""
export DESEC_TOKEN=""
export SCRIBE_GH_USER=""
export SCRIBE_GH_TOKEN=""
export ODIDO_TOKEN=""
export ODIDO_USER_ID=""

echo "Starting automated deployment..."

# Run full zima.sh with -y (confirm) -p (auto-passwords) -c (clean start)
sudo -E ./zima.sh -y -p -c

echo "Deployment finished."