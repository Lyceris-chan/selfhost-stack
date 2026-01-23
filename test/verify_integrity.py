#!/usr/bin/env python3
"""Project integrity and style compliance audit tool.

This script performs static analysis on the codebase to ensure adherence to
architectural patterns, UI standards (M3), and style guides (Google).
"""

import os
import re
import sys


class IntegrityChecker:
    """Checks the integrity and style compliance of the project."""

    def __init__(self):
        """Initializes the IntegrityChecker with zero counters."""
        self.passed = 0
        self.failed = 0
        self.warnings = 0

    def log_pass(self, msg: str):
        """Logs a passing check.

        Args:
            msg: The message to log.
        """
        print(f"  \033[32m[PASS]\033[0m {msg}")
        self.passed += 1

    def log_fail(self, msg: str):
        """Logs a failing check.

        Args:
            msg: The message to log.
        """
        print(f"  \033[31m[FAIL]\033[0m {msg}")
        self.failed += 1

    def log_warn(self, msg: str):
        """Logs a warning check.

        Args:
            msg: The message to log.
        """
        print(f"  \033[33m[WARN]\033[0m {msg}")
        self.warnings += 1

    def check_file_exists(self, path: str) -> bool:
        """Checks if a file exists.

        Args:
            path: Path to the file.

        Returns:
            True if exists, False otherwise.
        """
        if os.path.exists(path):
            return True
        self.log_fail(f"File not found: {path}")
        return False

    def check_pattern(
        self, path: str, pattern: str, description: str, literal: bool = False
    ) -> bool:
        """Checks if a pattern exists in a file.

        Args:
            path: Path to the file.
            pattern: The regex or literal string to search for.
            description: Description of the check.
            literal: If True, treats pattern as literal string.

        Returns:
            True if found, False otherwise.
        """
        if not self.check_file_exists(path):
            return False
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        found = False
        if literal:
            if pattern in content:
                found = True
        else:
            if re.search(pattern, content, re.MULTILINE):
                found = True

        if found:
            self.log_pass(description)
            return True
        else:
            self.log_fail(f"{description} (Pattern not found: {pattern[:50]}...)")
            return False

    def check_no_pattern(self, path: str, pattern: str, description: str) -> bool:
        """Checks if a pattern does NOT exist in a file.

        Args:
            path: Path to the file.
            pattern: The regex to search for (should not be present).
            description: Description of the check.

        Returns:
            True if not found, False if found.
        """
        if not self.check_file_exists(path):
            return False
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        if re.search(pattern, content, re.MULTILINE):
            self.log_fail(
                f"{description} (Pattern FOUND but should be absent: {pattern})"
            )
            return False
        else:
            self.log_pass(description)
            return True

    def verify_backend_logic(self):
        """Verifies backend logic and permissions."""
        print("\n--- Verifying Backend Logic & Permissions ---")
        self.check_pattern(
            "lib/core/core.sh",
            r'SELECTED_SERVICES=\$\(echo "\$STACK_SERVICES" \| sed',
            "Dynamic Odido-booster exclusion logic",
        )
        self.check_pattern(
            "lib/core/core.sh",
            r'\$SUDO chown 1000:1000 "\$HISTORY_LOG"',
            "Correct log file ownership (1000:1000)",
        )

    def verify_ui_standards(self):
        """Verifies M3 UI standards and layout."""
        print("\n--- Verifying M3 UI Standards & Layout ---")
        css = "lib/templates/assets/dashboard.css"
        html = "lib/templates/dashboard.html"

        self.check_pattern(
            css,
            r"\.section-label\s*\{[^}]*margin:\s*48px 0 24px 0",
            "Section labels follow 8dp grid",
        )
        self.check_pattern(
            css,
            r"\.flex-column\s*\{[^}]*flex-direction:\s*column",
            "Flex-column helper uses correct property",
        )

        # Updated check for tooltip-based description
        vpn_desc = "Services routed through the secure VPN tunnel"
        self.check_pattern(
            html,
            vpn_desc,
            "VPN mandated description present in dashboard.html (Tooltip)",
            literal=True,
        )

    def verify_style_guide(self):
        """Verifies adherence to style guides and terminology standards."""
        print("\n--- Verifying Google Style Guide Compliance ---")
        html = "lib/templates/dashboard.html"
        readme = "README.md"

        # Terminologies (Sentence case preferred for headers)
        self.check_pattern(html, r"Admin sign in", "Uses 'sign-in' instead of 'login'")
        self.check_no_pattern(
            html,
            r"[^/]Login",
            "No 'Login' found in dashboard template (excluding URLs)",
        )
        self.check_no_pattern(readme, r"Login", "No 'Login' found in README.md")

        # No Em Dashes (Restricted to project code/docs, ignoring third-party data)
        for root, _, files in os.walk("."):
            # Ignore external data and node_modules
            if any(
                x in root
                for x in [
                    "node_modules",
                    ".git",
                    "data/AppData",
                    "test/test_data",
                    "google-styleguides",
                    "google-styleguides-toon",
                ]
            ):
                continue
            for file in files:
                if file.endswith((".md", ".html", ".sh", ".py", ".js")):
                    if file == "styles.md":
                        continue
                    path = os.path.join(root, file)
                    self.check_no_pattern(path, "\u2014", f"No em dashes in {path}")

        # No Nonsensical Markers
        self.check_no_pattern(
            "zima.sh", r"SECTION \d:", "No SECTION markers in zima.sh"
        )
        self.check_no_pattern(
            "lib/core/core.sh", r"SECTION \d:", "No SECTION markers in core.sh"
        )

    def run(self):
        """Runs all verification checks."""
        print("==================================================")
        print("🛡️  ZIMAOS PRIVACY HUB: INTEGRITY AUDIT")
        print("==================================================")

        self.verify_backend_logic()
        self.verify_ui_standards()
        self.verify_style_guide()

        print("\n==================================================")
        print("AUDIT COMPLETE")
        print(f"  ✅ Passed:   {self.passed}")
        print(f"  ❌ Failed:   {self.failed}")
        print("==================================================")

        if self.failed > 0:
            sys.exit(1)


if __name__ == "__main__":
    IntegrityChecker().run()
