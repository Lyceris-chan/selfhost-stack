#!/usr/bin/env python3
from pathlib import Path
import re
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: format_wg.py <file_path>")
        sys.exit(1)

    path = Path(sys.argv[1])
    try:
        text = path.read_text()
        text = text.replace("\r", "")
        lines = text.splitlines()
        while lines and not lines[0].strip():
            lines.pop(0)
        lines = [line.rstrip() for line in lines]
        lines = [re.sub(r"\s*=\s*", "=", line) for line in lines]
        path.write_text("\n".join(lines) + ("\n" if lines else ""))
    except Exception as e:
        print(f"Error formatting file: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

