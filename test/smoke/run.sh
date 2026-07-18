#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
docker build -f test/smoke/Dockerfile.ubuntu -t groundcrew-smoke .
echo "SMOKE PASSED"
