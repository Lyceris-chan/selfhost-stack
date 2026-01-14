import os

import requests

from ..core.config import settings
from .logging import log_structured


def ensure_assets():
    """Verifies and initializes essential UI assets and branding icons.

    Ensures the existence of the assets directory and generates a default SVG
    application icon if one does not exist.
    """
    try:
        if not os.path.exists(settings.ASSETS_DIR):
            os.makedirs(settings.ASSETS_DIR, exist_ok=True)
        
        # Generate SVG Icon if missing
        app_name_raw = settings.APP_NAME
        app_name = "".join([c if c.isalnum() else '-' for c in app_name_raw]).lower()
        while '--' in app_name: app_name = app_name.replace('--', '-')
        app_name = app_name.strip('-')
        
        svg_path = os.path.join(settings.ASSETS_DIR, f"{app_name}.svg")
        if not os.path.exists(svg_path):
            svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
    <rect width="128" height="128" rx="28" fill="#141218"/>
    <path d="M64 104q-23-6-38-26.5T11 36v-22l53-20 53 20v22q0 25-15 45.5T64 104Zm0-14q17-5.5 28.5-22t11.5-35V21L64 6 24 21v12q0 18.5 11.5 35T64 90Zm0-52Z" fill="#D0BCFF" transform="translate(0, 15) scale(1)"/>
    <circle cx="64" cy="55" r="12" fill="#D0BCFF" opacity="0.8"/>
</svg>"""
            with open(svg_path, "w", encoding="utf-8") as f:
                f.write(svg)
            log_structured("INFO", f"Generated {app_name}.svg", "ASSETS")
            
    except Exception as e:
        log_structured("WARN", f"Asset ensure failed: {e}", "ASSETS")
