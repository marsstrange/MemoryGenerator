#!/usr/bin/env bash
# Opens painting_visualizer.pde in the Processing IDE, passing the file directly as an
# argument -- this doesn't depend on the OS having a .pde file-type association
# registered (which a portable/extracted Processing install often lacks).
# Does NOT auto-run the sketch: press the Run (play) button inside Processing yourself.
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

# Processing is usually a portable extracted app, not a system install, so its location
# varies per machine and can't be reliably auto-discovered. Check, in order: an explicit
# env var, PATH, the usual macOS app bundle location, then a path remembered from a
# previous run on this machine. If all of those fail, ask once and remember the answer
# (in a gitignored file) so nobody has to pre-configure anything themselves.
CACHE_FILE="$SCRIPT_DIR/.processing_ide_path"
PROC=""

if [ -n "$PROCESSING_APP" ] && [ -e "$PROCESSING_APP" ]; then
    PROC="$PROCESSING_APP"
elif command -v processing >/dev/null 2>&1; then
    PROC="processing"
elif [ -d "/Applications/Processing.app" ]; then
    PROC="/Applications/Processing.app"
elif [ -f "$CACHE_FILE" ]; then
    CACHED="$(cat "$CACHE_FILE")"
    if [ -e "$CACHED" ]; then
        PROC="$CACHED"
    fi
fi

if [ -z "$PROC" ]; then
    echo "Could not find the Processing IDE automatically."
    read -r -p "Enter the full path to Processing (the .app on macOS, or the 'processing' launcher on Linux): " TYPED
    if [ -n "$TYPED" ] && [ -e "$TYPED" ]; then
        PROC="$TYPED"
        echo "$PROC" > "$CACHE_FILE"
        echo "Saved -- future runs on this machine will find it automatically."
    else
        echo "No valid path given."
        exit 1
    fi
fi

echo "Opening $PDE_FILE in Processing: $PROC"
if [[ "$PROC" == *.app ]]; then
    open -a "$PROC" "$PDE_FILE"
else
    "$PROC" "$PDE_FILE" &
    disown
fi
