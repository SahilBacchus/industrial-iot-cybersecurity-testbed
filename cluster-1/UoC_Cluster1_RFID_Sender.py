# Note: Generative AI tools were used only to refine the explanations and technical justifications for clarity, not to generate the entire code.


from mfrc522 import MFRC522
import network
import time
import json
import ubinascii
import ntptime
from simple import MQTTClient


# =====================================================
# SMART GRID - CLUSTER 1 RFID SENDER
# Raspberry Pi Pico W + MFRC522
# =====================================================


# =====================================================
# WIFI CONFIGURATION
# =====================================================

SSID = "YOUR_SSID"
PASSWORD = "YOUR_PASSWORD"

GATEWAY = "192.168.1.1"

# Aggregator Raspberry Pi / MQTT Broker
MQTT_BROKER = "192.168.1.100"


# =====================================================
# DEVICE CONFIGURATION
# CHANGE FOR EACH RFID PICO
# =====================================================

DEVICE_ID = "pico_11"
CLUSTER_ID = "SG1"

STATIC_IP = "192.168.1.20"

SUBNET_MASK = "255.255.255.0"
DNS_SERVER = "8.8.8.8"

DEVICE_TYPE = "rfid"


# =====================================================
# RFID READER CONFIGURATION
# =====================================================

# Pico 11:
# If one Pico has two RFID readers, we will configure
# the second reader separately.
READER_ID = "rfid_reader_01"


# =====================================================
# MQTT TOPIC
# =====================================================

MQTT_TOPIC = "smartgrid/{}/{}".format(
    CLUSTER_ID,
    DEVICE_ID
)


# =====================================================
# WIFI + STATIC IP
# =====================================================

wlan = network.WLAN(network.STA_IF)

wlan.active(True)

wlan.ifconfig((
    STATIC_IP,
    SUBNET_MASK,
    GATEWAY,
    DNS_SERVER
))

print("Connecting to WiFi...")

wlan.connect(
    SSID,
    PASSWORD
)

while not wlan.isconnected():
    time.sleep(1)

print("WiFi Connected")
print("Network Configuration:", wlan.ifconfig())


# =====================================================
# NTP TIME SYNCHRONIZATION
# =====================================================

try:

    ntptime.settime()

    print("RTC synchronized using Internet NTP")

except Exception as e:

    print("Internet NTP failed:", e)

    try:

        ntptime.host = MQTT_BROKER
        ntptime.settime()

        print(
            "RTC synchronized using local Aggregator NTP"
        )

    except Exception as e2:

        print(
            "NTP unavailable. Continuing:",
            e2
        )


# =====================================================
# DEVICE MAC ADDRESS
# =====================================================

DEVICE_MAC = ubinascii.hexlify(
    wlan.config("mac"),
    ":"
).decode()

print("Device ID:", DEVICE_ID)
print("Device IP:", STATIC_IP)
print("Device MAC:", DEVICE_MAC)
print("Device Type:", DEVICE_TYPE)
print("Reader ID:", READER_ID)


# =====================================================
# MQTT CLIENT
# =====================================================

client = MQTTClient(
    DEVICE_ID,
    MQTT_BROKER,
    keepalive=60
)


def mqtt_connect():

    try:

        client.connect()

        print("MQTT Connected")

    except Exception as e:

        print(
            "MQTT Connection Failed:",
            e
        )


mqtt_connect()


# =====================================================
# RFID READER INITIALIZATION
# =====================================================

reader = MFRC522(
    spi_id=0,
    sck=6,
    miso=4,
    mosi=7,
    cs=5,
    rst=22
)

print("RFID Reader Initialized")
print("Bring TAG closer...")


# =====================================================
# SEQUENCE COUNTER
# =====================================================

seq = 0


# =====================================================
# SIMPLE DEBOUNCE
# Prevent continuously publishing the same tag while
# it remains sitting on the reader.
# =====================================================

last_card = None
last_card_time = 0

DEBOUNCE_TIME = 2


# =====================================================
# MAIN RFID LOOP
# =====================================================

while True:

    try:

        reader.init()

        stat, tag_type = reader.request(
            reader.REQIDL
        )


        # =================================================
        # TAG DETECTED
        # =================================================

        if stat == reader.OK:

            stat, uid = reader.SelectTagSN()


            if stat == reader.OK:

                # Convert UID to integer
                card_id = int.from_bytes(
                    bytes(uid),
                    "little",
                    False
                )


                current_time = time.time()


                # =========================================
                # DEBOUNCE
                # =========================================

                if (
                    card_id == last_card
                    and
                    current_time - last_card_time
                    < DEBOUNCE_TIME
                ):

                    time.sleep_ms(200)
                    continue


                last_card = card_id
                last_card_time = current_time

                seq += 1


                # =========================================
                # SMART GRID RFID PAYLOAD
                # NO INTENT INFORMATION
                # =========================================

                data = {

                    "device_id":
                        DEVICE_ID,

                    "cluster_id":
                        CLUSTER_ID,

                    "device_ip":
                        STATIC_IP,

                    "mac":
                        DEVICE_MAC,

                    "seq":
                        seq,

                    "send_time":
                        current_time,

                    "device_type":
                        DEVICE_TYPE,

                    "reader_id":
                        READER_ID,

                    "card_id":
                        str(card_id),

                    "event":
                        "tag_detected"
                }


                # =========================================
                # MQTT PUBLISH
                # =========================================

                client.publish(
                    MQTT_TOPIC,
                    json.dumps(data)
                )


                print(
                    "--------------------------------"
                )

                print(
                    "TAG DETECTED"
                )

                print(
                    "Reader:",
                    READER_ID
                )

                print(
                    "Card ID:",
                    card_id
                )

                print(
                    "Sequence:",
                    seq
                )

                print(
                    "Sent:",
                    data
                )

                print(
                    "--------------------------------"
                )


    except Exception as e:

        print(
            "RFID Sender Error:",
            e
        )


        # =============================================
        # MQTT RECONNECT
        # =============================================

        try:

            client.disconnect()

        except:

            pass


        time.sleep(2)

        mqtt_connect()


    # RFID polling interval
    time.sleep_ms(200)