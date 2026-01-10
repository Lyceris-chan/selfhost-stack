#!/usr/bin/env bash
set -e

# Production Verification Wrapper
export APP_NAME=privacy-hub-test
export PROJECT_ROOT=$(pwd)/test/test_data
export WG_CONF_B64="W0ludGVyZmFjZV0KUHJpdmF0ZUtleSA9IHZLRzhvS0ZMT0RWY0pPVFVZclBYYVFrSmtoTElyNmZ6NmZ6NmZ6NmZ6bmc9CkFkZHJlc3MgPSAxMC4yLjAuMi8zMgoKW1BlZXJdClB1YmxpY0tleSA9IHZLRzhvS0ZMT0RWY0pPVFVZclBYYVFrSmtoTElyNmZ6NmZ6NmZ6NmZ6bmc9CkVuZHBvaW50ID0gMS4xLjEuMTo1MTgyMApBbGxvd2VkSVBzID0gMC4wLjAuMC8wCg=="

echo "=========================================================="
echo " 🛡️  PRIVACY HUB: MANUAL VERIFICATION SUITE"
echo "=========================================================="

# Ensure test directory exists
mkdir -p test/test_data

# Run the python test runner
python3 test/test_runner.py --full

echo ""
echo "Verification complete."