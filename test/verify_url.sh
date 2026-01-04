#!/bin/bash
set -u

service=$1
url=$2
expected_code=${3:-200}

echo "Verifying $service at $url..."
for i in {1..45}; do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")
    if [ "$code" == "$expected_code" ]; then
        echo "[PASS] $service is UP (Status $code)"
        exit 0
    fi
    sleep 2
done
echo "[FAIL] $service is DOWN (Last status $code)"
exit 1
