#!/bin/bash

# WARNING: THIS SCRIPT IS A WORK IN PROGRESS
# currently the edge server is launched and works fine but the aggregator doesnt work for some reason




# Prevent Git Bash on Windows from translating Linux paths
export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION BLOCK
# ==============================================================================

# Device 1 Settings (nano18 - Edge Server)
DEV1_USER="nano18"
DEV1_IP="192.168.0.122"
EDGE_DIR="/home/nano18/Desktop/industrial-iot-cybersecurity-testbed/cluster-1/edge"

# Device 2 Settings (pi15 - Aggregator)
DEV2_USER="pi15"
DEV2_IP="192.168.0.25"
AGG_DIR="/home/pi15/Desktop/industrial-iot-cybersecurity-testbed/cluster-1/aggregator"

# Runtime variable for sudo password (entered interactively, not hardcoded)
SUDO_PASS=""

# ==============================================================================
# FUNCTIONS
# ==============================================================================

start_aggregator() {
    local duration_min=$1
    if [ "$duration_min" -eq 0 ]; then
        echo -e "\n---> Starting Aggregator on ${DEV2_USER}@${DEV2_IP} (Indefinite)..."
        ssh -n "${DEV2_USER}@${DEV2_IP}" "mkdir -p ${AGG_DIR} && cd ${AGG_DIR} && (nohup python3 UoC_Cluster1_Aggregator.py > aggregator.log 2>&1 &)"
    else
        echo -e "\n---> Starting Aggregator on ${DEV2_USER}@${DEV2_IP} for ${duration_min} minute(s)..."
        ssh -n "${DEV2_USER}@${DEV2_IP}" "mkdir -p ${AGG_DIR} && cd ${AGG_DIR} && (nohup timeout ${duration_min}m python3 UoC_Cluster1_Aggregator.py > aggregator.log 2>&1 &)"
    fi
}

start_edge() {
    local duration_min=$1
    
    # Prompt interactively for sudo password at runtime (not hardcoded)
    if [ -z "$SUDO_PASS" ]; then
        read -s -p "Enter sudo password for ${DEV1_USER}@${DEV1_IP}: " SUDO_PASS
        echo
    fi

    if [ "$duration_min" -eq 0 ]; then
        echo -e "\n---> Starting Edge Server components on ${DEV1_USER}@${DEV1_IP} (Indefinite)..."
        ssh -n "${DEV1_USER}@${DEV1_IP}" "mkdir -p ${EDGE_DIR} && cd ${EDGE_DIR} && (echo '$SUDO_PASS' | sudo -S nohup python3 UoC_Cluster1_Edgeserver.py > edgeserver.log 2>&1 &)"
        ssh -n "${DEV1_USER}@${DEV1_IP}" "mkdir -p ${EDGE_DIR} && cd ${EDGE_DIR} && (echo '$SUDO_PASS' | sudo -S nohup python3 UoC_Cluster1_Capture_Manager.py > capture.log 2>&1 &)"
    else
        echo -e "\n---> Starting Edge Server components on ${DEV1_USER}@${DEV1_IP} for ${duration_min} minute(s)..."
        ssh -n "${DEV1_USER}@${DEV1_IP}" "mkdir -p ${EDGE_DIR} && cd ${EDGE_DIR} && (echo '$SUDO_PASS' | sudo -S nohup timeout ${duration_min}m python3 UoC_Cluster1_Edgeserver.py > edgeserver.log 2>&1 &)"
        ssh -n "${DEV1_USER}@${DEV1_IP}" "mkdir -p ${EDGE_DIR} && cd ${EDGE_DIR} && (echo '$SUDO_PASS' | sudo -S nohup timeout ${duration_min}m python3 UoC_Cluster1_Capture_Manager.py > capture.log 2>&1 &)"
    fi
}

cleanup() {
    echo -e "\n\n---> Aborting: Forcing manual shutdown of remote cluster processes..."
    ssh -n "${DEV2_USER}@${DEV2_IP}" "pkill -f UoC_Cluster1_Aggregator.py"
    if [ -n "$SUDO_PASS" ]; then
        ssh -n "${DEV1_USER}@${DEV1_IP}" "echo '$SUDO_PASS' | sudo -S pkill -f UoC_Cluster1_Edgeserver.py"
        ssh -n "${DEV1_USER}@${DEV1_IP}" "echo '$SUDO_PASS' | sudo -S pkill -f UoC_Cluster1_Capture_Manager.py"
    else
        ssh -n "${DEV1_USER}@${DEV1_IP}" "sudo pkill -f UoC_Cluster1_Edgeserver.py"
        ssh -n "${DEV1_USER}@${DEV1_IP}" "sudo pkill -f UoC_Cluster1_Capture_Manager.py"
    fi
    echo "Remote cluster stopped. Exiting."
    exit 0
}

# Trap Ctrl+C (SIGINT) to allow early manual abortion if needed
trap cleanup INT

# ==============================================================================
# PROMPT & EXECUTION
# ==============================================================================

echo "=========================================================="
echo "          SMART GRID CLUSTER-1 LAUNCHER"
echo "=========================================================="
echo "Target Nodes:"
echo " - Aggregator:  ${DEV2_USER}@${DEV2_IP}"
echo " - Edge Server: ${DEV1_USER}@${DEV1_IP}"
echo "=========================================================="
read -p "Do you want to start the entire cluster now? (y/n): " CONFIRM

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    read -p "Enter test duration in minutes (or type 0 for indefinite run): " DURATION

    echo -e "\n---> Launching Cluster-1..."
    start_aggregator "$DURATION"
    sleep 2
    start_edge "$DURATION"
    
    if [ "$DURATION" -gt 0 ]; then
        echo -e "\nCluster successfully launched with a remote timeout of ${DURATION} minute(s)."
        echo "The remote nodes will automatically shut down on schedule."
        echo "You can safely disconnect your laptop from the network now."
    else
        echo -e "\nCluster is running indefinitely. Press Ctrl+C to abort and stop all nodes."
        while true; do sleep 1; done
    fi
else
    echo "Startup aborted."
    exit 0
fi