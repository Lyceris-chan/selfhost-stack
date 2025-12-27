#!/usr/bin/env bash
source internal/tests/creds.env
export WG_CONF_B64=$(base64 -w 0 internal/tests/wg_test.conf)
sudo -E bash zima.sh -y -p -c