#!/usr/bin/env python3
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
TEMPLATE_PATH = REPO_ROOT / "lib/templates/dashboard.html"
CSS_PATH = REPO_ROOT / "lib/templates/assets/dashboard.css"
JS_PATH = REPO_ROOT / "lib/templates/assets/dashboard.js"
OUTPUT_PATH = Path(os.environ.get("DASHBOARD_OUTPUT", SCRIPT_DIR / "dashboard.html"))

replacements = {
    "$LAN_IP": os.environ.get("LAN_IP", "127.0.0.1"),
    "$DESEC_DOMAIN": os.environ.get("DESEC_DOMAIN", "example.local"),
    "$PORT_PORTAINER": os.environ.get("PORT_PORTAINER", "9000"),
    "$BASE_DIR": "/app",
    "$PORT_DASHBOARD_WEB": "8081",
    "$APP_NAME": "privacy-hub",
    "$CURRENT_SLOT": os.environ.get("CURRENT_SLOT", "a")
}

if not TEMPLATE_PATH.exists():
    print(f"Template not found at {TEMPLATE_PATH}", file=sys.stderr)
    sys.exit(1)

html = TEMPLATE_PATH.read_text(encoding="utf-8")

# Inject CSS
if "{{DHI_CSS}}" in html:
    css = CSS_PATH.read_text(encoding="utf-8") if CSS_PATH.exists() else "/* CSS MISSING */"
    html = html.replace("{{DHI_CSS}}", css)

# Inject JS
if "{{DHI_JS}}" in html:
    js = JS_PATH.read_text(encoding="utf-8") if JS_PATH.exists() else "// JS MISSING"
    html = html.replace("{{DHI_JS}}", js)

# Replace variables
for key, val in replacements.items():
    html = html.replace(key, val)

# Also handle literal ${} style
html = html.replace("${CURRENT_SLOT}", replacements["$CURRENT_SLOT"])

OUTPUT_PATH.write_text(html, encoding="utf-8")
print(f"Dashboard generated at {OUTPUT_PATH}")