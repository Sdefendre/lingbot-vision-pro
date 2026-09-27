#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -warnings-as-errors \
    LingBotSpatial/Models/ReconstructionModels.swift \
    LingBotSpatial/Engine/PLYLoader.swift \
    tests/main.swift -o "$TEST_DIR/geometry-tests"
for name in reordered short missing-coordinates missing-end dark-colors element-scope pose; do
    "$TEST_DIR/geometry-tests" "$name"
done
