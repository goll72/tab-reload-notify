#!/bin/sh
# Runs tests inside a VM.
#
# Dependencies: `quickget`, `quickemu`

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
OUT_DIR="$REPO_ROOT/scripts/output/vms"

mkdir -p "$OUT_DIR"

. "$REPO_ROOT/scripts/common.sh"

