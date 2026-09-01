#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

# Configuration
INTERFACE="${1:-}"
OUTPUT_DIR="$HOME/pcap_captures"
DURATION=3600
FILESIZE=512000 # Size in KB (~500MB)

# Dynamic interface check
if [ -z "$INTERFACE" ]; then
    echo "Error: No interface specified."
    echo "Usage: ./capture.sh <mirrored_interface>"
    echo ""
    echo "Available network interfaces:"
    ip -o link show | awk -F': ' '{print "  - " $2}'
    exit 1
fi

# Ensure dumpcap is available
if ! command -v dumpcap &> /dev/null; then
    echo "Error: dumpcap could not be found. Please install wireshark-common/dumpcap."
    exit 1
fi

# Automatically create the directory if it does not exist
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi
chmod 777 "$OUTPUT_DIR"

echo "=================================================="
echo "Starting Wireshark Dumpcap Capture"
echo "Interface:  $INTERFACE"
echo "Output Dir: $OUTPUT_DIR"
echo "Rotation:   Every ${DURATION}s or $((FILESIZE / 1024))MB per file"
echo "=================================================="

# Execute dumpcap using internal sudo
exec sudo dumpcap -i "$INTERFACE" \
  -b duration:"$DURATION" \
  -b filesize:"$FILESIZE" \
  -w "$OUTPUT_DIR/capture.pcap"