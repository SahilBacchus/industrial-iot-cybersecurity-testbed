# Note: Generative AI tools were used only to refine the explanations and technical justifications for clarity, not to generate the entire code.

import csv
import os
import json
import threading
import time
import queue

from datetime import datetime, date

import paho.mqtt.client as mqtt
import requests


# =====================================================
# SMART GRID - CLUSTER 1 AGGREGATOR
#
# Supports:
#   - two_temp
#   - two_gas
#   - RFID
#
# Aggregator IP: 192.168.0.25
# Jetson Nano IP: 192.168.0.122
# =====================================================


# =====================================================
# CONFIGURATION
# =====================================================

DATA_DIR = "smartgrid_data"

# Mosquitto runs locally on this Raspberry Pi
MQTT_BROKER = "localhost"

# Receive ALL Cluster-1 devices
MQTT_TOPIC = "smartgrid/SG1/#"

# Jetson Nano Edge Server
SERVER_URL = "http://192.168.0.122:8000/ingest"

# Must match API_KEY in UoC_Cluster1_EdgeServer.py (set both to None to disable)
API_KEY = None

# Don't let one POST balloon forever if the Jetson is briefly unreachable
MAX_BATCH_SIZE = 500

# Reuse one TCP connection instead of opening a new one every 10s
http_session = requests.Session()


# =====================================================
# GLOBAL VARIABLES
# =====================================================

lock = threading.Lock()

# Used to calculate inter-arrival time for each device
last_seen = {}

# Queue for forwarding data to Jetson
send_queue = queue.Queue()



summary_lock = threading.Lock()

# hour_key ("YYYY-MM-DD_HH") -> stats dict
hour_stats = {}


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


def _update_hour_stats(device, device_type, actual_interval, receive_time):

    hour_key = datetime.now().strftime("%Y-%m-%d_%H")

    with summary_lock:

        stats = hour_stats.setdefault(hour_key, _empty_hour_stats())

        stats["record_count"] += 1

        stats["by_device_type"][device_type] = (
            stats["by_device_type"].get(device_type, 0) + 1
        )

        stats["by_device_id"][device] = (
            stats["by_device_id"].get(device, 0) + 1
        )

        if isinstance(actual_interval, (int, float)) and actual_interval > 0:
            stats["interval_sum"] += actual_interval
            stats["interval_count"] += 1

        if stats["first_record_time"] is None:
            stats["first_record_time"] = receive_time
        stats["last_record_time"] = receive_time


def _write_hour_summary(hour_key, stats):

    date_part, hour_part = hour_key.split("_")

    folder = os.path.join(DATA_DIR, date_part)
    os.makedirs(folder, exist_ok=True)

    path = os.path.join(folder, "smartgrid_summary_{}.json".format(hour_part))

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
    # Kept separate from the CSV writer, so a slow/failed
    # summary write can never hold up per-record logging.

    while True:

        time.sleep(60)

        now_hour_key = datetime.now().strftime("%Y-%m-%d_%H")

        with summary_lock:
            completed = [h for h in hour_stats if h != now_hour_key]
            to_write = {h: hour_stats.pop(h) for h in completed}

        for hour_key, stats in to_write.items():
            _write_hour_summary(hour_key, stats)


# =====================================================
# CSV HEADER
# =====================================================

CSV_HEADER = [

    # -----------------------------
    # General information
    # -----------------------------

    "receive_timestamp",

    "device_id",
    "cluster_id",

    "device_ip",
    "mac",

    "seq",
    "send_time",

    "protocol",
    "device_type",


    # -----------------------------
    # Periodic sensor information
    # Used by temperature/gas
    # -----------------------------

    "profile",
    "min_interval",
    "max_interval",

    "actual_interval",


    # -----------------------------
    # Gas sensors
    # -----------------------------

    "gas1",
    "gas2",


    # -----------------------------
    # Temperature sensors
    # -----------------------------

    "temperature1",
    "humidity1",

    "temperature2",
    "humidity2",


    # -----------------------------
    # RFID
    # -----------------------------

    "reader_id",
    "card_id",
    "event"
]


# =====================================================
# CREATE DAILY DIRECTORY
# =====================================================

def today_dir():

    folder = os.path.join(
        DATA_DIR,
        date.today().isoformat()
    )

    os.makedirs(
        folder,
        exist_ok=True
    )

    return folder


# =====================================================
# CREATE HOURLY CSV FILE
# =====================================================

def current_csv_path():

    hour = datetime.now().strftime("%H")

    path = os.path.join(
        today_dir(),
        "smartgrid_data_{}.csv".format(hour)
    )

    # Create file + header if this hour's
    # CSV does not exist yet
    if not os.path.exists(path):

        with open(
            path,
            "w",
            newline=""
        ) as f:

            writer = csv.writer(f)

            writer.writerow(
                CSV_HEADER
            )

    return path


# =====================================================
# ADD DATA TO EDGE QUEUE
# =====================================================

def forward_to_edge(data):

    send_queue.put(
        data
    )


# =====================================================
# BATCH FORWARDING TO JETSON
# =====================================================

def batch_sender():

    while True:

        # Send accumulated records every 10 seconds
        time.sleep(10)

        batch = []


        # ---------------------------------------------
        # Collect queued records (capped so a long Jetson
        # outage doesn't build one giant POST)
        # ---------------------------------------------

        while not send_queue.empty() and len(batch) < MAX_BATCH_SIZE:

            batch.append(
                send_queue.get()
            )


        if not batch:

            continue


        # ---------------------------------------------
        # Send batch to Jetson
        # ---------------------------------------------

        headers = {}
        if API_KEY:
            headers["X-API-Key"] = API_KEY

        try:

            response = http_session.post(
                SERVER_URL,
                json=batch,
                headers=headers,
                timeout=5
            )

            if response.status_code != 200:
                raise RuntimeError(
                    "Jetson returned status {}".format(response.status_code)
                )

            print(
                "[EDGE] Sent:",
                len(batch),
                "records | Status:",
                response.status_code
            )


        except Exception as e:

            print(
                "[EDGE] Send failed:",
                e
            )


            # -----------------------------------------
            # Put records back if Jetson unavailable
            # -----------------------------------------

            for item in batch:

                send_queue.put(
                    item
                )


# =====================================================
# PROCESS RECEIVED DATA
# =====================================================

def process_and_store(data):

    # -------------------------------------------------
    # Basic device information
    # -------------------------------------------------

    device = data.get(
        "device_id",
        "UNKNOWN"
    )

    device_type = data.get(
        "device_type",
        "UNKNOWN"
    )


    # -------------------------------------------------
    # Aggregator receive time
    # -------------------------------------------------

    receive_time = time.time()


    # =================================================
    # CALCULATE INTER-ARRIVAL TIME
    # =================================================

    if device in last_seen:

        actual_interval = round(
            receive_time
            - last_seen[device],
            3
        )

    else:

        # First message from this device
        actual_interval = 0


    last_seen[device] = receive_time


    # =================================================
    # UPDATE HOURLY SUMMARY (in-memory, cheap)
    # =================================================

    _update_hour_stats(
        device,
        device_type,
        actual_interval,
        receive_time
    )


    # =================================================
    # CREATE CSV ROW
    # =================================================

    row = [

        # ---------------------------------------------
        # General
        # ---------------------------------------------

        datetime.now().strftime(
            "%Y-%m-%d %H:%M:%S.%f"
        ),

        device,

        data.get(
            "cluster_id"
        ),

        data.get(
            "device_ip"
        ),

        data.get(
            "mac"
        ),

        data.get(
            "seq"
        ),

        data.get(
            "send_time"
        ),

        "MQTT",

        device_type,


        # ---------------------------------------------
        # Sensor timing/profile
        # RFID will automatically have empty values
        # ---------------------------------------------

        data.get(
            "profile"
        ),

        data.get(
            "min_interval"
        ),

        data.get(
            "max_interval"
        ),

        actual_interval,


        # ---------------------------------------------
        # Gas
        # ---------------------------------------------

        data.get(
            "gas1"
        ),

        data.get(
            "gas2"
        ),


        # ---------------------------------------------
        # Temperature
        # ---------------------------------------------

        data.get(
            "temperature1"
        ),

        data.get(
            "humidity1"
        ),

        data.get(
            "temperature2"
        ),

        data.get(
            "humidity2"
        ),


        # ---------------------------------------------
        # RFID
        # Temperature/gas will have empty values
        # ---------------------------------------------

        data.get(
            "reader_id"
        ),

        data.get(
            "card_id"
        ),

        data.get(
            "event"
        )
    ]


    # =================================================
    # STORE LOCALLY
    # =================================================

    with lock:

        with open(
            current_csv_path(),
            "a",
            newline=""
        ) as f:

            writer = csv.writer(f)

            writer.writerow(
                row
            )


    # =================================================
    # TERMINAL OUTPUT
    # =================================================

    print("----------------------------------------")

    print(
        "[STORED]",
        "Device:",
        device,
        "| Type:",
        device_type,
        "| Seq:",
        data.get("seq"),
        "| Interval:",
        actual_interval
    )


    # =================================================
    # DISPLAY SENSOR-SPECIFIC INFORMATION
    # =================================================

    if device_type == "two_temp":

        print(
            "TEMP 1:",
            data.get("temperature1"),
            "| HUM 1:",
            data.get("humidity1")
        )

        print(
            "TEMP 2:",
            data.get("temperature2"),
            "| HUM 2:",
            data.get("humidity2")
        )


    elif device_type == "two_gas":

        print(
            "GAS 1:",
            data.get("gas1"),
            "| GAS 2:",
            data.get("gas2")
        )


    elif device_type == "rfid":

        print(
            "Reader:",
            data.get("reader_id"),
            "| Card:",
            data.get("card_id"),
            "| Event:",
            data.get("event")
        )


    print("----------------------------------------")


    # =================================================
    # PREPARE DATA FOR JETSON
    # =================================================

    enriched = data.copy()


    enriched.update({

        "receive_time":
            receive_time,

        "actual_interval":
            actual_interval,

        "protocol":
            "MQTT"
    })


    # =================================================
    # FORWARD ALL DATA TO JETSON
    # =================================================

    forward_to_edge(
        enriched
    )


# =====================================================
# MQTT CONNECTION CALLBACK
# =====================================================

def on_connect(
    client,
    userdata,
    flags,
    rc
):

    print(
        "MQTT Connected | RC:",
        rc
    )


    # Subscribe to ALL SG1 devices
    client.subscribe(
        MQTT_TOPIC
    )


    print(
        "Subscribed to:",
        MQTT_TOPIC
    )


# =====================================================
# MQTT MESSAGE CALLBACK
# =====================================================

def on_message(
    client,
    userdata,
    msg
):

    try:

        # ---------------------------------------------
        # Decode MQTT JSON
        # ---------------------------------------------

        payload = json.loads(
            msg.payload.decode()
        )


        print(
            "[MQTT]",
            msg.topic
        )


        # ---------------------------------------------
        # Process message
        # ---------------------------------------------

        process_and_store(
            payload
        )


    except Exception as e:

        print(
            "MQTT Processing Error:",
            e
        )


# =====================================================
# START MQTT CLIENT
# =====================================================

def start_mqtt():

    client = mqtt.Client()


    client.on_connect = (
        on_connect
    )

    client.on_message = (
        on_message
    )


    try:

        client.connect(
            MQTT_BROKER,
            1883,
            60
        )

        client.loop_forever()


    except Exception as e:

        print(
            "MQTT Connection Error:",
            e
        )


# =====================================================
# MAIN
# =====================================================

if __name__ == "__main__":

    print(
        "=========================================="
    )

    print(
        "SMART GRID CLUSTER-1 AGGREGATOR"
    )

    print(
        "=========================================="
    )

    print(
        "Aggregator IP : 192.168.0.25"
    )

    print(
        "MQTT Broker   :",
        MQTT_BROKER
    )

    print(
        "MQTT Topic    :",
        MQTT_TOPIC
    )

    print(
        "Jetson Edge   :",
        SERVER_URL
    )

    print(
        "Data Folder   :",
        os.path.abspath(DATA_DIR)
    )

    print(
        "=========================================="
    )

    print(
        "Waiting for Smart Grid devices..."
    )


    # =================================================
    # MQTT RECEIVER THREAD
    # =================================================

    threading.Thread(
        target=start_mqtt,
        daemon=True
    ).start()


    # =================================================
    # JETSON FORWARDING THREAD
    # =================================================

    threading.Thread(
        target=batch_sender,
        daemon=True
    ).start()


    # =================================================
    # HOURLY SUMMARY THREAD
    # =================================================

    threading.Thread(
        target=hourly_summary_flusher,
        daemon=True
    ).start()


    # =================================================
    # KEEP AGGREGATOR RUNNING
    # =================================================

    while True:

        time.sleep(60)