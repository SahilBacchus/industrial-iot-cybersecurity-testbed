# Note: Generative AI tools were used only to refine the explanations and technical justifications for clarity, not to generate the entire code.


"""
UoC_Cluster1_EdgeServer.py

SMART GRID - CLUSTER 1 EDGE SERVER
Runs on: Jetson Nano (192.168.1.200)

Receives batched JSON records posted by the Aggregator
(UoC_Cluster1_Aggregator.py, via its batch_sender thread)
at POST /ingest, and stores them locally as:
    - hourly CSV files (human-readable, same style as aggregator)
    - a SQLite database (easy to query later for analysis)

Install (on the Jetson):
    pip3 install fastapi "uvicorn[standard]"

Run:
    python3 UoC_Cluster1_EdgeServer.py
    (or: uvicorn UoC_Cluster1_EdgeServer:app --host 0.0.0.0 --port 8000)
"""

import os
import csv
import json
import sqlite3
import threading
import time

from datetime import datetime, date
from typing import List, Dict, Any, Optional

from fastapi import FastAPI, Request, HTTPException
import uvicorn


# =====================================================
# CONFIGURATION
# =====================================================

DATA_DIR = "edge_data"
DB_PATH = os.path.join(DATA_DIR, "smartgrid_edge.db")

HOST = "0.0.0.0"
PORT = 8000

# Optional shared secret. If set, the aggregator must send this
# value in an "X-API-Key" header, otherwise requests are rejected.
# Set to None to disable the check (fine for a closed lab network).
API_KEY: Optional[str] = None


CSV_HEADER = [
    "receive_timestamp_edge",

    "device_id",
    "cluster_id",
    "device_ip",
    "mac",

    "seq",
    "send_time",
    "receive_time_aggregator",
    "actual_interval",

    "protocol",
    "device_type",

    "profile",
    "min_interval",
    "max_interval",

    "gas1",
    "gas2",

    "temperature1",
    "humidity1",
    "temperature2",
    "humidity2",

    "reader_id",
    "card_id",
    "event",
]


# =====================================================
# GLOBALS
# =====================================================

lock = threading.Lock()
total_received = 0

os.makedirs(DATA_DIR, exist_ok=True)



summary_lock = threading.Lock()

# hour_key ("YYYY-MM-DD_HH") -> stats dict
hour_stats: Dict[str, Dict[str, Any]] = {}


def _empty_hour_stats():

    return {
        "record_count": 0,
        "by_device_type": {},
        "by_device_id": {},
        "interval_sum": 0.0,
        "interval_count": 0,
        "first_record_time": None,
        "last_record_time": None,
    }


def _update_hour_stats(device, device_type, actual_interval, receive_ts_edge):

    hour_key = datetime.now().strftime("%Y-%m-%d_%H")

    with summary_lock:

        stats = hour_stats.setdefault(hour_key, _empty_hour_stats())

        stats["record_count"] += 1

        stats["by_device_type"][device_type or "UNKNOWN"] = (
            stats["by_device_type"].get(device_type or "UNKNOWN", 0) + 1
        )

        stats["by_device_id"][device or "UNKNOWN"] = (
            stats["by_device_id"].get(device or "UNKNOWN", 0) + 1
        )

        if isinstance(actual_interval, (int, float)) and actual_interval > 0:
            stats["interval_sum"] += actual_interval
            stats["interval_count"] += 1

        if stats["first_record_time"] is None:
            stats["first_record_time"] = receive_ts_edge
        stats["last_record_time"] = receive_ts_edge


def _write_hour_summary(hour_key, stats):

    date_part, hour_part = hour_key.split("_")

    folder = os.path.join(DATA_DIR, date_part)
    os.makedirs(folder, exist_ok=True)

    path = os.path.join(folder, "edge_summary_{}.json".format(hour_part))

    avg_interval = (
        round(stats["interval_sum"] / stats["interval_count"], 3)
        if stats["interval_count"] else None
    )

    summary = {
        "hour": hour_key,
        "record_count": stats["record_count"],
        "by_device_type": stats["by_device_type"],
        "by_device_id": stats["by_device_id"],
        "avg_actual_interval": avg_interval,
        "first_record_time": stats["first_record_time"],
        "last_record_time": stats["last_record_time"],
    }

    with open(path, "w") as f:
        json.dump(summary, f, indent=2)

    print("[SUMMARY] Wrote hourly summary:", path)


def hourly_summary_flusher():

    # Checks every minute for any hour bucket that is no
    # longer the current hour, and flushes it to disk.

    while True:

        time.sleep(60)

        now_hour_key = datetime.now().strftime("%Y-%m-%d_%H")

        with summary_lock:
            completed = [h for h in hour_stats if h != now_hour_key]
            to_write = {h: hour_stats.pop(h) for h in completed}

        for hour_key, stats in to_write.items():
            _write_hour_summary(hour_key, stats)

app = FastAPI(title="Smart Grid Cluster-1 Edge Server")


# =====================================================
# SQLITE SETUP
# =====================================================

def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS readings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            receive_timestamp_edge TEXT,
            device_id TEXT,
            cluster_id TEXT,
            device_ip TEXT,
            mac TEXT,
            seq INTEGER,
            send_time REAL,
            receive_time_aggregator REAL,
            actual_interval REAL,
            protocol TEXT,
            device_type TEXT,
            profile TEXT,
            min_interval REAL,
            max_interval REAL,
            gas1 REAL,
            gas2 REAL,
            temperature1 REAL,
            humidity1 REAL,
            temperature2 REAL,
            humidity2 REAL,
            reader_id TEXT,
            card_id TEXT,
            event TEXT,
            raw_json TEXT
        )
    """)
    conn.commit()
    conn.close()


def insert_rows(rows):
    """rows: list of tuples matching the readings table column order (minus id)."""
    conn = sqlite3.connect(DB_PATH)
    conn.executemany("""
        INSERT INTO readings (
            receive_timestamp_edge, device_id, cluster_id, device_ip, mac,
            seq, send_time, receive_time_aggregator, actual_interval,
            protocol, device_type, profile, min_interval, max_interval,
            gas1, gas2, temperature1, humidity1, temperature2, humidity2,
            reader_id, card_id, event, raw_json
        ) VALUES (?,?,?,?,?, ?,?,?,?, ?,?,?,?,?, ?,?,?,?,?,?, ?,?,?,?)
    """, rows)
    conn.commit()
    conn.close()


init_db()


# =====================================================
# CSV STORAGE (hourly files, same layout as the aggregator)
# =====================================================

def today_dir():
    folder = os.path.join(DATA_DIR, date.today().isoformat())
    os.makedirs(folder, exist_ok=True)
    return folder


def current_csv_path():
    hour = datetime.now().strftime("%H")
    path = os.path.join(today_dir(), "edge_data_{}.csv".format(hour))

    if not os.path.exists(path):
        with open(path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(CSV_HEADER)

    return path


# =====================================================
# STORE A SINGLE RECORD (CSV + SQLite row tuple)
# =====================================================

def store_record(data: Dict[str, Any], receive_ts_edge: str):

    row = [
        receive_ts_edge,

        data.get("device_id"),
        data.get("cluster_id"),
        data.get("device_ip"),
        data.get("mac"),

        data.get("seq"),
        data.get("send_time"),
        data.get("receive_time"),      # set by aggregator's process_and_store()
        data.get("actual_interval"),

        data.get("protocol"),
        data.get("device_type"),

        data.get("profile"),
        data.get("min_interval"),
        data.get("max_interval"),

        data.get("gas1"),
        data.get("gas2"),

        data.get("temperature1"),
        data.get("humidity1"),
        data.get("temperature2"),
        data.get("humidity2"),

        data.get("reader_id"),
        data.get("card_id"),
        data.get("event"),
    ]

    with open(current_csv_path(), "a", newline="") as f:
        csv.writer(f).writerow(row)

    return tuple(row) + (json.dumps(data),)


# =====================================================
# INGEST ENDPOINT
# =====================================================

@app.post("/ingest")
async def ingest(request: Request):

    global total_received

    if API_KEY is not None:
        if request.headers.get("X-API-Key") != API_KEY:
            raise HTTPException(status_code=401, detail="Invalid API key")

    try:
        batch: List[Dict[str, Any]] = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Body must be a JSON array of records")

    if not isinstance(batch, list):
        raise HTTPException(status_code=400, detail="Expected a JSON array of records")

    receive_ts_edge = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")

    sqlite_rows = []

    with lock:
        for data in batch:
            if not isinstance(data, dict):
                continue
            sqlite_rows.append(store_record(data, receive_ts_edge))
            _update_hour_stats(
                data.get("device_id"),
                data.get("device_type"),
                data.get("actual_interval"),
                receive_ts_edge
            )

        if sqlite_rows:
            insert_rows(sqlite_rows)

        total_received += len(sqlite_rows)

    print("[INGEST] Received {} records | Total so far: {}".format(
        len(sqlite_rows), total_received
    ))

    return {"status": "ok", "received": len(sqlite_rows)}


# =====================================================
# HEALTH / STATUS ENDPOINTS
# =====================================================

@app.get("/health")
async def health():
    return {"status": "up", "time": time.time()}


@app.get("/status")
async def status():
    with lock:
        return {
            "total_received": total_received,
            "db_path": os.path.abspath(DB_PATH),
            "data_dir": os.path.abspath(DATA_DIR),
        }


# =====================================================
# MAIN
# =====================================================

if __name__ == "__main__":

    print("==========================================")
    print("SMART GRID CLUSTER-1 EDGE SERVER")
    print("==========================================")
    print("Listening on : {}:{}".format(HOST, PORT))
    print("Data folder  :", os.path.abspath(DATA_DIR))
    print("SQLite DB    :", os.path.abspath(DB_PATH))
    print("API key auth :", "ENABLED" if API_KEY else "disabled")
    print("==========================================")

    threading.Thread(
        target=hourly_summary_flusher,
        daemon=True
    ).start()

    uvicorn.run(app, host=HOST, port=PORT)