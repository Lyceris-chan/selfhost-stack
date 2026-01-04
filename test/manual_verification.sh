#!/bin/bash
# Wrapper to run the Python Orchestrator

# Ensure we are running from the project root so that paths in deployment_todos.json are valid
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

python3 "$SCRIPT_DIR/orchestrator.py"
