#!/bin/bash
#
# Deployment Verification Wrapper.
# Delegates to the comprehensive verification suite in test/bin.
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SUITE_PATH="${SCRIPT_DIR}/test/bin/verify_suite.sh"

if [[ -f "${SUITE_PATH}" ]]; then
  exec "${SUITE_PATH}" "$@"
else
  echo "Error: Verification suite not found at ${SUITE_PATH}" >&2
  exit 1
fi