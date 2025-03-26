#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
$SCRIPT_DIR/build/linux/x64/release/bundle/wine_prefix_manager
