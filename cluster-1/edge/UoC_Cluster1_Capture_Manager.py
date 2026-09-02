# Note: Generative AI tools were used only to refine the explanations and technical justifications for clarity, not to generate the entire code.

"""
UoC_Cluster1_Capture_Manager.py

SMART GRID - CLUSTER 1 EDGE SERVER - NETWORK CAPTURE MANAGER
Runs on: Jetson Nano (192.168.1.200), alongside UoC_Cluster1_Edgeserver.py

Install (on the Jetson):
    sudo apt install tcpdump 
Run:
    sudo python3 UoC_Cluster1_Capture_Manager.py

Recommended: manage it with systemd so it restarts on boot/crash.
"""

import os
import glob
import gzip
import shutil
import signal
import subprocess
import threading
import time

from datetime import datetime, timedelta


# =====================================================
# CONFIGURATION
# =====================================================

# Network interface to capture on (change to match the Jetson's
# monitoring NIC / mirror port / tap)
IFACE = "eth0"

DATA_DIR = "edge_data"

PCAP_DIR = os.path.join(DATA_DIR, "pcap")
ZEEK_LIVE_DIR = os.path.join(DATA_DIR, "zeek_logs", "_live")
ZEEK_ARCHIVE_DIR = os.path.join(DATA_DIR, "zeek_logs")

# Rotate the pcap file every hour, OR every 500 MB -- whichever
# happens first (tcpdump supports both triggers natively).
PCAP_ROTATE_SECONDS = 3600
PCAP_MAX_SIZE_MB = 500          

# How often Zeek is restarted (this is how its logs get "rotated")
ZEEK_ROTATE_SECONDS = 3600

# How often to check/create today's + tomorrow's pcap directories
DIR_PRECREATE_INTERVAL = 600    # 10 minutes


# =====================================================
# GLOBALS
# =====================================================

stop_event = threading.Event()

tcpdump_proc = None
zeek_proc = None


# =====================================================
# UTILITIES
# =====================================================

def _require_binary(name):
    path = shutil.which(name)
    if path is None:
        raise RuntimeError(
            "Required binary '{}' not found on PATH. "
            "Install it first (e.g. sudo apt install {}).".format(name, name)
        )
    return path


def _gzip_and_remove(src_path):
    """Compress src_path to src_path.gz, then delete the original."""

    dst_path = src_path + ".gz"

    with open(src_path, "rb") as f_in:
        with gzip.open(dst_path, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)

    os.remove(src_path)

    return dst_path


def pcap_dir_precreator():

    while not stop_event.is_set():

        today = datetime.now().date()
        tomorrow = today + timedelta(days=1)

        for d in (today, tomorrow):
            folder = os.path.join(PCAP_DIR, d.isoformat())
            os.makedirs(folder, exist_ok=True)

        stop_event.wait(DIR_PRECREATE_INTERVAL)


# =====================================================
# TCPDUMP MANAGEMENT
# =====================================================

def start_tcpdump():

    global tcpdump_proc

    _require_binary("tcpdump")

    os.makedirs(PCAP_DIR, exist_ok=True)

    # strftime pattern: PCAP_DIR/YYYY-MM-DD/edge_YYYYMMDD_HHMMSS.pcap
    out_pattern = os.path.join(
        PCAP_DIR, "%Y-%m-%d", "edge_%Y%m%d_%H%M%S.pcap"
    )

    cmd = [
        "tcpdump",
        "-i", IFACE,
        "-w", out_pattern,
        "-G", str(PCAP_ROTATE_SECONDS),   # rotate every N seconds...
        "-C", str(PCAP_MAX_SIZE_MB),      # ...or every N MB, whichever first
        "-z", "gzip",                     # gzip each file once it's rotated
        "-n",                             # don't resolve hostnames (faster)
    ]

    print("[TCPDUMP] Starting:", " ".join(cmd))

    tcpdump_proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    return tcpdump_proc


def tcpdump_watchdog():

    # Restarts tcpdump if it dies unexpectedly (e.g. interface
    # briefly disappeared). Rotation itself is handled internally
    # by tcpdump via -G / -C, so this thread does NOT need to
    # restart it every hour -- only on crash.

    start_tcpdump()

    while not stop_event.is_set():

        if tcpdump_proc.poll() is not None:

            _, stderr = tcpdump_proc.communicate()

            print(
                "[TCPDUMP] Process exited unexpectedly (code {}): {}".format(
                    tcpdump_proc.returncode,
                    stderr.decode(errors="replace").strip()
                )
            )

            if stop_event.is_set():
                break

            print("[TCPDUMP] Restarting in 5s...")
            time.sleep(5)
            start_tcpdump()

        stop_event.wait(5)


# =====================================================
# ZEEK MANAGEMENT
# =====================================================

def start_zeek():

    global zeek_proc

    _require_binary("zeek")

    if os.path.exists(ZEEK_LIVE_DIR):
        shutil.rmtree(ZEEK_LIVE_DIR)
    os.makedirs(ZEEK_LIVE_DIR, exist_ok=True)

    cmd = ["zeek", "-i", IFACE]

    print("[ZEEK] Starting:", " ".join(cmd), "| cwd:", ZEEK_LIVE_DIR)

    zeek_proc = subprocess.Popen(
        cmd,
        cwd=ZEEK_LIVE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    return zeek_proc


def stop_zeek(proc, timeout=30):

    if proc is None or proc.poll() is not None:
        return

    # SIGTERM lets Zeek flush and close its log files cleanly
    proc.terminate()

    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        print("[ZEEK] Did not exit in time, killing...")
        proc.kill()
        proc.wait()


def archive_zeek_logs():

    """Move+gzip everything in ZEEK_LIVE_DIR into
    ZEEK_ARCHIVE_DIR/<date>/<hour>/ for the hour that just finished."""

    log_files = glob.glob(os.path.join(ZEEK_LIVE_DIR, "*.log"))

    if not log_files:
        print("[ZEEK] No log files to archive this hour.")
        return

    # Use the hour that just ended, not "now" (in case archiving
    # runs a few seconds into the new hour)
    hour_ts = datetime.now() - timedelta(minutes=1)

    dest_folder = os.path.join(
        ZEEK_ARCHIVE_DIR,
        hour_ts.strftime("%Y-%m-%d"),
        hour_ts.strftime("%H"),
    )
    os.makedirs(dest_folder, exist_ok=True)

    for log_path in log_files:

        filename = os.path.basename(log_path)
        dest_path = os.path.join(dest_folder, filename)

        try:
            shutil.move(log_path, dest_path)
            gz_path = _gzip_and_remove(dest_path)
            print("[ZEEK] Archived:", gz_path)
        except Exception as e:
            print("[ZEEK] Failed to archive {}: {}".format(filename, e))

    # Clean up any other Zeek working files left behind (.status,
    # .cmdline, .pid etc.) so the live dir starts empty next hour
    for leftover in glob.glob(os.path.join(ZEEK_LIVE_DIR, "*")):
        try:
            if os.path.isfile(leftover):
                os.remove(leftover)
        except Exception:
            pass


def _seconds_until_next_hour():

    now = datetime.now()
    next_hour = (now + timedelta(hours=1)).replace(
        minute=0, second=0, microsecond=0
    )
    return (next_hour - now).total_seconds()


def zeek_hourly_manager():

    start_zeek()

    # Align the first restart to the top of the next hour, then
    # every ZEEK_ROTATE_SECONDS after that.
    wait_seconds = _seconds_until_next_hour()

    while not stop_event.is_set():

        if stop_event.wait(wait_seconds):
            break

        print("[ZEEK] Hourly rotation triggered.")

        stop_zeek(zeek_proc)
        archive_zeek_logs()
        start_zeek()

        wait_seconds = ZEEK_ROTATE_SECONDS


# =====================================================
# SHUTDOWN HANDLING
# =====================================================

def _handle_shutdown(signum, frame):

    print("\n[CAPTURE MANAGER] Shutdown signal received, stopping...")
    stop_event.set()


# =====================================================
# MAIN
# =====================================================

if __name__ == "__main__":

    signal.signal(signal.SIGINT, _handle_shutdown)
    signal.signal(signal.SIGTERM, _handle_shutdown)

    print("==========================================")
    print("SMART GRID CLUSTER-1 CAPTURE MANAGER")
    print("==========================================")
    print("Interface       :", IFACE)
    print("PCAP folder     :", os.path.abspath(PCAP_DIR))
    print("PCAP rotation   : every {}s or {} MB".format(
        PCAP_ROTATE_SECONDS, PCAP_MAX_SIZE_MB
    ))
    print("Zeek log folder :", os.path.abspath(ZEEK_ARCHIVE_DIR))
    print("Zeek rotation   : every {}s (restart + archive)".format(
        ZEEK_ROTATE_SECONDS
    ))
    print("==========================================")

    threads = [
        threading.Thread(target=pcap_dir_precreator, daemon=True),
        threading.Thread(target=tcpdump_watchdog, daemon=True),
        threading.Thread(target=zeek_hourly_manager, daemon=True),
    ]

    for t in threads:
        t.start()

    try:
        while not stop_event.is_set():
            time.sleep(1)
    except KeyboardInterrupt:
        stop_event.set()

    # =================================================
    # CLEAN SHUTDOWN
    # =================================================

    if tcpdump_proc is not None and tcpdump_proc.poll() is None:
        print("[CAPTURE MANAGER] Stopping tcpdump...")
        tcpdump_proc.terminate()
        try:
            tcpdump_proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            tcpdump_proc.kill()

    if zeek_proc is not None and zeek_proc.poll() is None:
        print("[CAPTURE MANAGER] Stopping Zeek and archiving final logs...")
        stop_zeek(zeek_proc)
        archive_zeek_logs()

    print("[CAPTURE MANAGER] Stopped.")
