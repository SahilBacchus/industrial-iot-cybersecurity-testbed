#!/bin/bash

# Remember to connect to the same network as the devices you are trying to pull from

# ==============================================================================
# CONFIG (Edit here to change IPs, Users, or Paths)
# ==============================================================================

# Local Destination --> This is configured as windows download folder for currently signed in user
BASE_LOCAL_DIR="/c/Users/${USERNAME}/Downloads"

# Device 1 Settings (nano18)
DEV1_USER="nano18"
DEV1_IP="192.168.0.122"
DEV1_PATHS=(
    "/home/nano18/Desktop/industrial-iot-cybersecurity-testbed/cluster-1/edge/edge_data/"
)

# Device 2 Settings (pi15)
DEV2_USER="pi15"
DEV2_IP="192.168.0.25"
DEV2_PATHS=(
    "/home/pi15/Desktop/industrial-iot-cybersecurity-testbed/cluster-1/aggregator/smartgrid_data"
)

# ==============================================================================
# AUTOMATION PORTION
# ==============================================================================

# Create a unique timestamped folder
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
TARGET_DIR="${BASE_LOCAL_DIR}/Testbed_Data_${TIMESTAMP}"
mkdir -p "$TARGET_DIR"

echo "=========================================================="
echo "  TESTBED REMOTE CLUSTER DATA DOWNLOAD"
echo "=========================================================="
echo "Saving files to: ${TARGET_DIR}"
echo "----------------------------------------------------------"
echo "Which device do you want to pull data from?"
echo "1) ${DEV1_USER} (${DEV1_IP})"
echo "2) ${DEV2_USER} (${DEV2_IP})"
echo "3) Both devices"
echo "=========================================================="
read -p "Enter choice [1-3]: " CHOICE

# ------------------------------------------------------------------------------
# DEVICE 1 EXECUTION
# ------------------------------------------------------------------------------
if [ "$CHOICE" -eq 1 ] || [ "$CHOICE" -eq 3 ]; then
    echo -e "\n---> Processing ${DEV1_USER} (${DEV1_IP})..."
    echo "Note: You will be prompted for your password once per directory path."
    
    for REMOTE_PATH in "${DEV1_PATHS[@]}"; do
        echo "Downloading: ${REMOTE_PATH}"
        scp -r "${DEV1_USER}@${DEV1_IP}:${REMOTE_PATH}" "$TARGET_DIR"
    done
fi

# ------------------------------------------------------------------------------
# DEVICE 2 EXECUTION
# ------------------------------------------------------------------------------
if [ "$CHOICE" -eq 2 ] || [ "$CHOICE" -eq 3 ]; then
    echo -e "\n---> Processing ${DEV2_USER} (${DEV2_IP})..."
    echo "Note: You will be prompted for your password once per directory path."
    
    for REMOTE_PATH in "${DEV2_PATHS[@]}"; do
        echo "Downloading: ${REMOTE_PATH}"
        scp -r "${DEV2_USER}@${DEV2_IP}:${REMOTE_PATH}" "$TARGET_DIR"
    done
fi

echo -e "\nDone! Selected files have been safely copied to: $TARGET_DIR"
