#!/usr/bin/env bash
# Launches SuperCollider headless (no IDE window) against SC_mood_reactive.scd.
# Runs detached in the background -- since there's no window to show postln output,
# it's redirected to sclang.log instead (tail -f it to watch for
# "Mood-reactive receiver ready on port 12001." or any errors).
# To stop it: kill the PID this script prints, or `pkill -f sclang`.
#
# Usage: bash run_supercollider.sh   (or: chmod +x run_supercollider.sh && ./run_supercollider.sh)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCD_FILE="$SCRIPT_DIR/../audio_playback/SC_mood_reactive.scd"
LOG_FILE="$SCRIPT_DIR/sclang.log"

if command -v sclang >/dev/null 2>&1; then
    SCLANG="sclang"
elif [ -x "/Applications/SuperCollider.app/Contents/MacOS/sclang" ]; then
    SCLANG="/Applications/SuperCollider.app/Contents/MacOS/sclang"
elif [ -x "/Applications/SuperCollider.app/Contents/Resources/sclang" ]; then
    SCLANG="/Applications/SuperCollider.app/Contents/Resources/sclang"
else
    echo "Could not find sclang. Either add it to PATH, or edit this script with the full path."
    exit 1
fi

if [ ! -f "$SCD_FILE" ]; then
    echo "Could not find $SCD_FILE"
    exit 1
fi

# scsynth (the audio server, a separate binary from sclang) is looked up by bare name
# when sclang boots the server -- add its directory to PATH in case it isn't already
# (it lives right alongside sclang in the same install/bundle directory)
if [[ "$SCLANG" == /* ]]; then
    export PATH="$(dirname "$SCLANG"):$PATH"
fi

echo "Starting SuperCollider (headless): $SCLANG \"$SCD_FILE\""
echo "Log: $LOG_FILE"
nohup "$SCLANG" "$SCD_FILE" > "$LOG_FILE" 2>&1 &
disown
echo "Started (PID $!). To stop: kill $!  (or: pkill -f sclang)"
