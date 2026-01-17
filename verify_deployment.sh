#!/bin/bash
echo "=========================================="
echo "DEPLOYMENT VERIFICATION SCRIPT"
echo "=========================================="
echo ""

# Verify script structure
echo "✓ Checking script components..."
grep -q "setup_secrets\|setup_configs\|setup_static_assets" zima.sh && echo "  ✓ Environment setup found" || echo "  ✗ Missing environment setup"
grep -q "deploy_stack" lib/services/deploy.sh && echo "  ✓ Service deployment found" || echo "  ✗ Missing service deployment"
grep -q "generate_compose" lib/services/compose.sh && echo "  ✓ Compose generation found" || echo "  ✗ Missing compose generation"

echo ""
echo "✓ Checking configuration files..."
test -f lib/templates/dashboard.html && echo "  ✓ Dashboard template exists" || echo "  ✗ Missing dashboard template"
test -f lib/templates/wg_control.sh && echo "  ✓ WireGuard control script exists" || echo "  ✗ Missing WG control"

echo ""
echo "✓ Syntax validation..."
for script in lib/core/*.sh lib/services/*.sh; do
  if bash -n "$script" 2>/dev/null; then
    echo "  ✓ $(basename $script)"
  else
    echo "  ✗ $(basename $script) has syntax errors"
    bash -n "$script"
  fi
done

echo ""
echo "=========================================="
echo "VERIFICATION COMPLETE"
echo "=========================================="
