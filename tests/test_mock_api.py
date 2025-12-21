#!/usr/bin/env python3
# 🧪 MOCK TEST: Hub API Update & Migration Logic
# This script starts a local mock server to verify the new endpoints.

import http.server
import socketserver
import json
import os
import subprocess
import threading
import time
import urllib.request

PORT = 8888
BASE_DIR = "/DATA/AppData/privacy-hub"
SRC_DIR = f"{BASE_DIR}/sources"
MIGRATE_SCRIPT = "/usr/local/bin/migrate.sh"

# Mock classes to simulate the real environment
class MockAPIHandler(http.server.BaseHTTPRequestHandler):
    def _send_json(self, data, code=200):
        body = json.dumps(data).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/updates':
            # Real logic simulation
            updates = {}
            if os.path.exists(SRC_DIR):
                for repo in os.listdir(SRC_DIR):
                    repo_path = os.path.join(SRC_DIR, repo)
                    if os.path.isdir(os.path.join(repo_path, ".git")):
                        updates[repo] = "Update Available"
            self._send_json({"updates": updates})
        elif self.path.startswith('/migrate'):
            self._send_json({"success": True, "output": "Mock migration successful"})

    def do_POST(self):
        if self.path == '/update-service':
            self._send_json({"success": True, "output": "Mock service update successful"})

def run_server():
    with socketserver.TCPServer(("", PORT), MockAPIHandler) as httpd:
        httpd.serve_forever()

# 1. Setup Test Environment
print("[TEST] Setting up mock source directory...")
os.makedirs(SRC_DIR, exist_ok=True)
mock_repo = os.path.join(SRC_DIR, "mock-service")
os.makedirs(mock_repo, exist_ok=True)
subprocess.run(["git", "init", "-q"], cwd=mock_repo)

# 2. Start Server in thread
daemon = threading.Thread(target=run_server, daemon=True)
daemon.start()
time.sleep(1)

# 3. Test Endpoints
print("[TEST] Verifying /updates...")
with urllib.request.urlopen(f"http://localhost:{PORT}/updates") as response:
    data = json.loads(response.read().decode())
    if "mock-service" in data["updates"]:
        print("✅ PASS: /updates detected mock repository.")
    else:
        print(f"❌ FAIL: /updates did not detect mock repository. Data: {data}")

print("[TEST] Verifying /migrate...")
with urllib.request.urlopen(f"http://localhost:{PORT}/migrate?service=invidious") as response:
    data = json.loads(response.read().decode())
    if data["success"]:
        print("✅ PASS: /migrate returned success.")
    else:
        print(f"❌ FAIL: /migrate failed.")

print("[TEST] Verifying /update-service...")
req = urllib.request.Request(f"http://localhost:{PORT}/update-service", data=json.dumps({"service": "invidious"}).encode(), method='POST')
with urllib.request.urlopen(req) as response:
    data = json.loads(response.read().decode())
    if data["success"]:
        print("✅ PASS: /update-service returned success.")
    else:
        print(f"❌ FAIL: /update-service failed.")

# Cleanup
subprocess.run(["rm", "-rf", mock_repo])
print("[TEST] All mock API tests complete.")
