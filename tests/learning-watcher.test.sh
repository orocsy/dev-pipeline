#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 -m unittest discover -s "$ROOT/tools/learning-watcher/tests" -p 'test_*.py' -q
echo "PASS: learning watcher"
