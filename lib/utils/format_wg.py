#!/usr/bin/env python3
"""WireGuard configuration formatter.

This script ensures WireGuard .conf files are correctly formatted for Gluetun
and handles environment-specific endpoint overrides.
"""

import os
import re
import sys
from pathlib import Path


def main():
    """Main execution for formatting WireGuard configuration files."""
    if len(sys.argv) < 2:
        print("Usage: format_wg.py <file_path>")
        sys.exit(1)

    path = Path(sys.argv[1])
    env_path = path.parent / "gluetun.env"
    
    try:
        text = path.read_text()
        text = text.replace("\r", "")
        lines = text.splitlines()
        while lines and not lines[0].strip():
            lines.pop(0)
        # Apply test environment fix and basic formatting
        final_lines = []
        for line in lines:
            line = re.sub(r"\s*=\s*", "=", line.rstrip())
            # Fix for test environment where endpoint is 127.0.0.1
            if line.lower().startswith("endpoint"):
                if "127.0.0.1" in line:
                    line = line.replace("127.0.0.1", "172.20.0.1")
            final_lines.append(line)
        
        # Save formatted config back
        path.write_text("\n".join(final_lines) + ("\n" if final_lines else ""))
        print(f"Formatted {path}")

    except Exception as e:
        print(f"Error processing file: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

