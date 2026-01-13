#!/usr/bin/env bash
set -e

# ==========================================================
# 🛡️  ZIMAOS PRIVACY HUB: MASTER TEST SUITE
# ==========================================================
# This script orchestrates all levels of verification:
# 1. Integrity Audit (File-level standards)
# 2. Functional Suite (Connectivity & API)
# 3. UI/UX Audit (Browser interactions)
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Step 1: Running Integrity Audit..."
python3 test/verify_integrity.py

echo ""
echo "Step 2: Running Functional & API Suite..."
# Set up test environment
export APP_NAME=privacy-hub-test
export PROJECT_ROOT_DIR="$PROJECT_ROOT/test/test_data"
mkdir -p "$PROJECT_ROOT_DIR"

# Note: test_runner.py handles its own deployment if --full is passed
# For CI/CD efficiency, we might skip full runner if integrity fails
python3 test/test_runner.py --full

echo ""
echo "Step 3: Running UI/UX Audit..."
node test/verify_ui.js

echo ""
echo "=========================================================="
echo " ✅ ALL VERIFICATIONS PASSED"
echo "=========================================================="
