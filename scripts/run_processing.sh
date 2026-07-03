#!/usr/bin/env bash
# Opens painting_visualizer.pde in whatever app the OS associates with .pde files
# (the Processing IDE, if installed) -- same as double-clicking the file yourself.
# It does NOT auto-run the sketch: press the Run (play) button inside Processing once
# it opens. This avoids needing to locate processing-java at all.
#
# Usage: bash run_processing.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKETCH_DIR="$(cd "$SCRIPT_DIR/../painting_visualizer" && pwd)"
PDE_FILE="$SKETCH_DIR/painting_visualizer.pde"

if [ ! -f "$PDE_FILE" ]; then
    echo "Could not find $PDE_FILE"
    exit 1
fi

echo "Opening $PDE_FILE ..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    open "$PDE_FILE"
else
    xdg-open "$PDE_FILE"
fi
