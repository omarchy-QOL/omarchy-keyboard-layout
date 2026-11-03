#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
make -C native all test
node --test tests/layout-state.test.mjs tests/keyboard-viewer.test.mjs
node tests/run-qml.mjs
