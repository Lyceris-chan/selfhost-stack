#!/usr/bin/env python3
from pathlib import Path
import re
import sys
import os

def main():
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
        lines = [line.rstrip() for line in lines]
        lines = [re.sub(r"\s*=\s*", "=", line) for line in lines]
        
        # Save formatted config back
        path.write_text("\n".join(lines) + ("\n" if lines else ""))
        
        # Parse for Gluetun
        conf = {}
        section = None
        for line in lines:
            line = line.strip()
            if not line or line.startswith("#"): continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1].lower()
                continue
            
            if "=" in line:
                key, val = line.split("=", 1)
                key = key.strip().lower()
                val = val.strip()
                if section == "interface":
                    if key == "privatekey": conf["private_key"] = val
                    elif key == "address": conf["addresses"] = val
                    elif key == "dns": conf["dns"] = val
                elif section == "peer":
                    if key == "publickey": conf["public_key"] = val
                    elif key == "presharedkey": conf["preshared_key"] = val
                    elif key == "endpoint":
                        if ":" in val:
                            parts = val.split(":")
                            conf["endpoint_ip"] = parts[0]
                            conf["endpoint_port"] = parts[1]
                        else:
                            conf["endpoint_ip"] = val
                            conf["endpoint_port"] = "51820"
        
        # Generate env content
        env_content = [
            "VPN_SERVICE_PROVIDER=custom",
            "VPN_TYPE=wireguard",
            f"WIREGUARD_PRIVATE_KEY={conf.get('private_key', '')}",
            f"WIREGUARD_ADDRESSES={conf.get('addresses', '')}",
            f"VPN_ENDPOINT_IP={conf.get('endpoint_ip', '')}",
            f"VPN_ENDPOINT_PORT={conf.get('endpoint_port', '51820')}",
            f"WIREGUARD_PUBLIC_KEY={conf.get('public_key', '')}",
            f"WIREGUARD_DNS={conf.get('dns', '1.1.1.1')}",
            "FIREWALL_VPN_INPUT_PORTS=10416,8080,8180,3000,3002,8280,8480,80",
            "HTTPPROXY=on"
        ]
        
        if conf.get("preshared_key"):
            env_content.append(f"WIREGUARD_PRESHARED_KEY={conf['preshared_key']}")
            
        env_path.write_text("\n".join(env_content) + "\n")
        print(f"Generated {env_path}")

    except Exception as e:
        print(f"Error processing file: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

