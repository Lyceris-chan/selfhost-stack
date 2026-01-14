#!/usr/bin/env python3
"""Project integrity and style compliance audit tool.

This script performs static analysis on the codebase to ensure adherence to
architectural patterns, UI standards (M3), and style guides (Google).
"""

import os
import re
import sys
import json
import subprocess

class IntegrityChecker:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.warnings = 0

    def log_pass(self, msg):
        print(f"  \033[32m[PASS]\033[0m {msg}")
        self.passed += 1

    def log_fail(self, msg):
        print(f"  \033[31m[FAIL]\033[0m {msg}")
        self.failed += 1

    def log_warn(self, msg):
        print(f"  \033[33m[WARN]\033[0m {msg}")
        self.warnings += 1

    def check_file_exists(self, path):
        if os.path.exists(path):
            return True
        self.log_fail(f"File not found: {path}")
        return False

    def check_pattern(self, path, pattern, description, literal=False):
        if not self.check_file_exists(path): return False
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        found = False
        if literal:
            if pattern in content: found = True
        else:
            if re.search(pattern, content, re.MULTILINE): found = True
        
        if found:
            self.log_pass(description)
            return True
        else:
            self.log_fail(f"{description} (Pattern not found: {pattern[:50]}...)")
            return False

    def check_no_pattern(self, path, pattern, description):
        if not self.check_file_exists(path): return False
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        if re.search(pattern, content, re.MULTILINE):
            self.log_fail(f"{description} (Pattern FOUND but should be absent: {pattern})")
            return False
        else:
            self.log_pass(description)
            return True

    def verify_backend_logic(self):
        print("\n--- Verifying Backend Logic & Permissions ---")
        self.check_pattern("lib/core/core.sh", r'SELECTED_SERVICES=\$\(echo "\$STACK_SERVICES" \| sed', "Dynamic Odido-booster exclusion logic")
        self.check_pattern("lib/core/core.sh", r'\$SUDO chown 1000:1000 "\$HISTORY_LOG"', "Correct log file ownership (1000:1000)")

    def verify_ui_standards(self):
        print("\n--- Verifying M3 UI Standards & Layout ---")
        css = "lib/templates/assets/dashboard.css"
        html = "lib/templates/dashboard.html"
        
        self.check_pattern(css, r'\.section-label\s*\{[^}]*margin:\s*48px 0 16px 0', "Section labels follow 8dp grid")
        self.check_pattern(css, r'\.flex-column\s*\{[^}]*flex-direction:\s*column', "Flex-column helper uses correct property")
        
        vpn_desc = "Services marked with 🔒 VPN are routed through a secure tunnel. These services only access the internet via the VPN gateway and are not reachable from the public internet."
        self.check_pattern(html, vpn_desc, "VPN mandated description present in dashboard.html", literal=True)

    def verify_style_guide(self):
        print("\n--- Verifying Google Style Guide Compliance ---")
        html = "lib/templates/dashboard.html"
        readme = "README.md"
        
        # Terminologies
        self.check_pattern(html, r'Admin Sign in', "Uses 'sign-in' instead of 'login'")
        self.check_no_pattern(html, r'[^/]Login', "No 'Login' found in dashboard template (excluding URLs)")
        self.check_no_pattern(readme, r'Login', "No 'Login' found in README.md")

        # No Em Dashes (Restricted to project code/docs, ignoring third-party data)
        for root, dirs, files in os.walk("."):
            # Ignore external data and node_modules
            if any(x in root for x in ["node_modules", ".git", "data/AppData", "test/test_data"]):
                continue
            for file in files:
                if file.endswith((".md", ".html", ".sh", ".py", ".js")):
                    if file == "styles.md":
                        continue
                    path = os.path.join(root, file)
                    self.check_no_pattern(path, "\u2014", f"No em dashes in {path}")

        # No Nonsensical Markers
        self.check_no_pattern("zima.sh", r'SECTION \d:', "No SECTION markers in zima.sh")
        self.check_no_pattern("lib/core/core.sh", r'SECTION \d:', "No SECTION markers in core.sh")

    def run(self):
        print("==================================================")
        print("🛡️  ZIMAOS PRIVACY HUB: INTEGRITY AUDIT")
        print("==================================================")
        
        self.verify_backend_logic()
        self.verify_ui_standards()
        self.verify_style_guide()
        
        print("\n==================================================")
        print(f"AUDIT COMPLETE")
        print(f"  ✅ Passed:   {self.passed}")
        print(f"  ❌ Failed:   {self.failed}")
        print("==================================================")
        
        if self.failed > 0:
            sys.exit(1)

if __name__ == "__main__":
    IntegrityChecker().run()