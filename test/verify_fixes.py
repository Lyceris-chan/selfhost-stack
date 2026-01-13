#!/usr/bin/env python3
import os
import re
import sys

def check_file_content(filepath, pattern, description):
    if not os.path.exists(filepath):
        print(f"[FAIL] {description}: File not found: {filepath}")
        return False
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    if re.search(pattern, content, re.MULTILINE):
        print(f"[PASS] {description}")
        return True
    else:
        print(f"[FAIL] {description}: Pattern '{pattern}' not found in {filepath}")
        return False

def verify_fixes():
    print("=== Verifying Fixes ===")
    all_passed = True

    # 1. AdGuard YAML Quoting
    all_passed &= check_file_content(
        "lib/services/config.sh",
        r'echo "  - \\\"@@\\|\\|getproton.me\\^\\""',
        "AdGuard YAML config values are quoted"
    )

    # 2. Hub API Permissions (Secrets chown)
    all_passed &= check_file_content(
        "lib/core/core.sh",
        r'\$SUDO chown 1000:1000 "\$BASE_DIR/\.secrets"',
        "Secrets file ownership is corrected (chown 1000:1000)"
    )

    # 3. UI Text Update
    all_passed &= check_file_content(
        "lib/templates/dashboard.html",
        r'<h2 class="headline-small">Admin sign-in</h2>',
        "Dashboard login title updated to 'Admin sign-in'"
    )

    # 4. UI Layout Fix (Flex Shrink)
    all_passed &= check_file_content(
        "lib/templates/assets/dashboard.css",
        r'\.btn-icon.*flex-shrink: 0;',
        "Button icon flex-shrink fix applied"
    )

    # 5. SearXNG Config
    all_passed &= check_file_content(
        "lib/services/config.sh",
        r'autocomplete: "google"',
        "SearXNG autocomplete is set to 'google'"
    )

    # 6. Click-to-copy Codeblocks
    all_passed &= check_file_content(
        "lib/templates/dashboard.html",
        r'onclick="copyToClipboard',
        "Click-to-copy functionality added to code blocks"
    )

    # 7. Modal Header Alignment
    all_passed &= check_file_content(
        "lib/templates/assets/dashboard.css",
        r'\.modal-header\s*\{[^}]*display:\s*flex',
        "Modal header alignment styles added"
    )

    # 8. 8dp Grid Alignment
    all_passed &= check_file_content(
        "lib/templates/assets/dashboard.css",
        r'\.section-label\s*\{[^}]*margin:\s*48px 0 16px 0',
        "Section labels are aligned with the 8dp grid (margin-left: 0)"
    )

    # 9. Stat Row Vertical Layout
    all_passed &= check_file_content(
        "lib/templates/assets/dashboard.css",
        r'\.stat-row\s*\{[^}]*flex-direction:\s*column',
        "Stat rows use vertical stacking for better spacing"
    )

    if all_passed:
        print("\nAll targeted fixes verified successfully.")
        sys.exit(0)
    else:
        print("\nSome verifications failed.")
        sys.exit(1)

if __name__ == "__main__":
    verify_fixes()
