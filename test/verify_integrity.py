#!/usr/bin/env python3
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
        with open(path, 'r') as f:
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

    def verify_backend_logic(self):
        print("\n--- Verifying Backend Logic & Permissions ---")
        # 1. Odido exclusion
        self.check_pattern(
            "lib/core/core.sh",
            r'SELECTED_SERVICES=\$\(echo "\$STACK_SERVICES" \| sed',
            "Dynamic Odido-booster exclusion logic"
        )
        # 2. Permissions
        self.check_pattern(
            "lib/core/core.sh",
            r'\$SUDO touch "\$HISTORY_LOG"',
            "Root-level log file initialization with SUDO"
        )
        self.check_pattern(
            "lib/core/core.sh",
            r'\$SUDO chown 1000:1000 "\$HISTORY_LOG"',
            "Correct log file ownership (1000:1000)"
        )
        # 3. Hub API Redundancy
        path = "lib/src/hub-api/app/routers/system.py"
        if self.check_file_exists(path):
            with open(path, 'r') as f:
                content = f.read()
                count = content.count('def get_project_details')
                if count == 1:
                    self.log_pass("Redundant Hub API function definitions removed")
                else:
                    self.log_fail(f"Hub API contains {count} duplicate 'get_project_details' definitions")

    def verify_ui_standards(self):
        print("\n--- Verifying M3 UI Standards & Layout ---")
        css = "lib/templates/assets/dashboard.css"
        html = "lib/templates/dashboard.html"
        
        # 1. Spacing
        self.check_pattern(css, r'\.section-label\s*\{[^}]*margin:\s*48px 0 16px 0', "Section labels follow 8dp grid")
        self.check_pattern(css, r'\.stat-row\s*\{[^}]*flex-direction:\s*column', "Stat rows use vertical stacking for paths")
        
        # 2. Centering
        self.check_pattern(css, r'#odido-not-configured\s*\{[^}]*justify-content:\s*center', "Utility cards use flex centering")
        
        # 3. Alignment Fixes
        self.check_pattern(css, r'\.btn-icon\s*\{[^}]*flex-shrink:\s*0', "Icon buttons protected from squashing (flex-shrink: 0)")
        self.check_pattern(css, r'\.modal-header\s*\{[^}]*justify-content:\s*space-between', "Modal header alignment (Title vs Close)")

        # 4. Features
        self.check_pattern(html, r'onclick="copyToClipboard', "Click-to-copy integrated in templates")

    def verify_style_guide(self):
        print("\n--- Verifying Google Documentation Style Guide ---")
        readme = "README.md"
        html = "lib/templates/dashboard.html"
        
        # 1. Active Voice & Direct Instructions
        self.check_pattern(readme, r'The ZimaOS Privacy Hub is a comprehensive, self-hosted privacy infrastructure', "README uses active voice in subtitle")
        self.check_pattern(html, r'Redact identifying metrics to protect your privacy', "Dashboard tooltips follow style guide")
        self.check_pattern(html, r'Use IP links', "Dashboard labels are concise and direct")
        
        # 2. Capitalization
        self.check_pattern(html, r'<h2 class="headline-small">Admin sign-in</h2>', "Login title uses Sentence case")

    def verify_service_configs(self):
        print("\n--- Verifying Service Configurations ---")
        # 1. SearXNG
        self.check_pattern("lib/services/config.sh", r'autocomplete: \"google\"', "SearXNG autocomplete set to Google")
        self.check_pattern("lib/services/config.sh", r'image_proxy: true', "SearXNG image proxy enabled")
        
        # 2. AdGuard Home
        self.check_pattern("lib/services/config.sh", r'\"@@\\|\\|getproton.me\\^\"', "AdGuard YAML values are properly quoted")

    def run(self):
        print("==================================================")
        print("🛡️  ZIMAOS PRIVACY HUB: INTEGRITY AUDIT")
        print("==================================================")
        
        self.verify_backend_logic()
        self.verify_ui_standards()
        self.verify_style_guide()
        self.verify_service_configs()
        
        print("\n==================================================")
        print(f"AUDIT COMPLETE")
        print(f"  ✅ Passed:   {self.passed}")
        print(f"  ❌ Failed:   {self.failed}")
        print(f"  ⚠️  Warnings: {self.warnings}")
        print("==================================================")
        
        if self.failed > 0:
            sys.exit(1)

if __name__ == "__main__":
    IntegrityChecker().run()
