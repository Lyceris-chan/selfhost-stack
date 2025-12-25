#!/usr/bin/env python3
import os
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
ZIMA_PATH = REPO_ROOT / "zima.sh"
OUTPUT_PATH = Path(os.environ.get("DASHBOARD_OUTPUT", SCRIPT_DIR / "dashboard.html"))

replacements = {
    "LAN_IP": os.environ.get("LAN_IP", "127.0.0.1"),
    "DESEC_DOMAIN": os.environ.get("DESEC_DOMAIN", "example.local"),
    "ODIDO_API_KEY": os.environ.get("ODIDO_API_KEY", "mock_key"),
    "PORT_PORTAINER": os.environ.get("PORT_PORTAINER", "9000"),
}

if not ZIMA_PATH.exists():
    print(f"zima.sh not found at {ZIMA_PATH}", file=sys.stderr)
    sys.exit(1)

lines = ZIMA_PATH.read_text(encoding="utf-8").splitlines()
blocks = []

pattern = re.compile(r'cat\s+>>?\s+"\$DASHBOARD_FILE"\s+<<\'?EOF\'?')
for idx, line in enumerate(lines):
    if pattern.search(line):
        chunk = []
        cursor = idx + 1
        while cursor < len(lines) and lines[cursor] != "EOF":
            chunk.append(lines[cursor])
            cursor += 1
        blocks.append("\n".join(chunk))

if not blocks:
    print("No dashboard blocks found in zima.sh", file=sys.stderr)
    sys.exit(1)

html = "\n".join(blocks)

def replace_var(match):
    key = match.group(1)
    return replacements.get(key, match.group(0))

html = re.sub(r"\$([A-Z_][A-Z0-9_]*)", replace_var, html)
html = html.replace("\\`", "`").replace("\\${", "${")

OUTPUT_PATH.write_text(f"{html}\n", encoding="utf-8")
print(f"Dashboard generated at {OUTPUT_PATH}")
