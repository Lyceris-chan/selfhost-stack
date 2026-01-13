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
        # Use simpler search for debugging if regex fails
        if pattern.replace('\\', '') in content:
             print(f"[PASS] {description} (Literal match)")
             return True
        print(f"[FAIL] {description}: Pattern not found in {filepath}")
        return False

def verify_new_changes():
    print("=== Verifying New Changes (Odido exclusion, Style Guide, Centering) ===")
    all_passed = True

    # 1. Odido exclusion logic in core.sh
    # We check for the dynamic sed command
    all_passed &= check_file_content(
        "lib/core/core.sh",
        r'SELECTED_SERVICES=\$\(echo "\\$STACK_SERVICES" \| sed',
        "Odido exclusion logic uses dynamic STACK_SERVICES"
    )

    # 2. Style Guide - Dashboard Subtitle
    all_passed &= check_file_content(
        "lib/templates/dashboard.html",
        r'Secure your network and manage your private service infrastructure',
        "Dashboard subtitle updated to active voice"
    )

    # 3. Style Guide - Switch Tooltips
    all_passed &= check_file_content(
        "lib/templates/dashboard.html",
        r'data-tooltip="Redact identifying metrics to protect your privacy\."',
        "Privacy switch tooltip updated to follow style guide"
    )

    # 4. Centering - Odido not configured
    all_passed &= check_file_content(
        "lib/templates/assets/dashboard.css",
        r'#odido-not-configured\s*\{',
        "Odido not configured container has CSS base"
    )
    all_passed &= check_file_content(
        "lib/templates/assets/dashboard.js",
        r'notConf.style.display = \'flex\'',
        "Odido not configured container uses display: flex for centering"
    )

    # 5. Redundant code in Hub API
    with open("lib/src/hub-api/app/routers/system.py", 'r') as f:
        content = f.read()
        occurrences = content.count('def get_project_details')
        if occurrences == 1:
            print("[PASS] Redundant 'get_project_details' definitions removed")
        else:
            print(f"[FAIL] Redundant 'get_project_details' definitions still exist (found {occurrences})")
            all_passed = False

    # 6. Style Guide - Hub API README
    all_passed &= check_file_content(
        "lib/src/hub-api/README.md",
        r'This lightweight Python service manages the following tasks',
        "Hub API README updated to follow style guide"
    )

    if all_passed:
        print("\nAll new changes verified successfully.")
        sys.exit(0)
    else:
        print("\nSome verifications failed.")
        sys.exit(1)

if __name__ == "__main__":
    verify_new_changes()