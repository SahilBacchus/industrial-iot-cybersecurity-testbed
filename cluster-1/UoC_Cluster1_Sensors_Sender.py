# Note: Generative AI tools were used only to refine the explanations and technical justifications for clarity, not to generate the entire code.

from machine import ADC, Pin
import network
import time
import json
import random
import ubinascii
import ntptime
from simple import MQTTClient
import dht


# =====================================================
# SMART GRID - CLUSTER 1 SENDER
# Raspberry Pi Pico W
# Supports:
#   1. two_temp
#   2. two_gas
# =====================================================


# =====================================================
# WIFI CONFIGURATION
# =====================================================

SSID = "YOUR_SSID"
PASSWORD = "YOUR_PASSWORD"

# Router / Gateway
GATEWAY = "192.168.0.1"

# Raspberry Pi Aggregator + MQTT Broker
MQTT_BROKER = "192.168.0.25"


# =====================================================
# DEVICE CONFIGURATION
# CHANGE THESE FOR EACH PICO
# =====================================================

DEVICE_ID = "pico_01"
CLUSTER_ID = "SG1"

# OPTIONS:
# "two_temp"
# "two_gas"
SENSOR_MODE = "two_temp"

# Static IP for THIS Pico
STATIC_IP = "192.168.0.201"

SUBNET_MASK = "255.255.255.0"
DNS_SERVER = "8.8.8.8"


# =====================================================
# TRANSMISSION PROFILE
# =====================================================

PROFILE = "fast"

PROFILE_INTERVALS = {
    "fast": (5, 40),
    "medium": (30, 90),
    "slow": (60, 150)
}


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

# Assign static IP BEFORE connecting
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

print("Network Configuration:")
print(wlan.ifconfig())


# =====================================================
# NTP TIME SYNCHRONIZATION
# =====================================================

try:

    ntptime.settime()

    print("RTC synchronized using Internet NTP")

except Exception as e:

    print("Internet NTP failed:", e)

    try:

        # Local NTP server on Aggregator
        ntptime.host = MQTT_BROKER

        ntptime.settime()

        print("RTC synchronized using local Aggregator NTP")

    except Exception as e2:

        print(
            "NTP unavailable. Continuing without synchronization:",
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
print("Sensor Mode:", SENSOR_MODE)

time.sleep(2)


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
# SENSOR INITIALIZATION
# =====================================================

if SENSOR_MODE == "two_temp":

    # Temperature Sensor 1
    temp_sensor1 = dht.DHT11(
        Pin(16)
    )

    # Temperature Sensor 2
    temp_sensor2 = dht.DHT11(
        Pin(17)
    )

    print(
        "Two temperature sensors initialized"
    )


elif SENSOR_MODE == "two_gas":

    # Gas Sensor 1
    gas_sensor1 = ADC(
        Pin(28)
    )

    # Gas Sensor 2
    gas_sensor2 = ADC(
        Pin(27)
    )

    print(
        "Two gas sensors initialized"
    )


else:

    raise ValueError(
        "Invalid SENSOR_MODE"
    )


# =====================================================
# SEQUENCE COUNTER
# =====================================================

seq = 0


# =====================================================
# MAIN SENSOR LOOP
# =====================================================

while True:

    try:

        # ---------------------------------------------
        # Transmission timing
        # ---------------------------------------------

        min_t, max_t = PROFILE_INTERVALS[
            PROFILE
        ]

        sleep_time = random.randint(
            min_t,
            max_t
        )


        # ---------------------------------------------
        # Sequence number
        # ---------------------------------------------

        seq += 1


        # ---------------------------------------------
        # BASIC PAYLOAD
        # NO INTENT INFORMATION
        # ---------------------------------------------

        data = {

            "device_id": DEVICE_ID,

            "cluster_id": CLUSTER_ID,

            "device_ip": STATIC_IP,

            "mac": DEVICE_MAC,

            "seq": seq,

            "send_time": time.time(),

            "device_type": SENSOR_MODE,

            "profile": PROFILE,

            "min_interval": min_t,

            "max_interval": max_t
        }


        # =================================================
        # TWO TEMPERATURE SENSORS
        # =================================================

        if SENSOR_MODE == "two_temp":

            try:

                # Sensor 1
                temp_sensor1.measure()

                temperature1 = (
                    temp_sensor1.temperature()
                )

                humidity1 = (
                    temp_sensor1.humidity()
                )


                # Small delay between DHT readings
                time.sleep(1)


                # Sensor 2
                temp_sensor2.measure()

                temperature2 = (
                    temp_sensor2.temperature()
                )

                humidity2 = (
                    temp_sensor2.humidity()
                )


                data["temperature1"] = temperature1
                data["humidity1"] = humidity1

                data["temperature2"] = temperature2
                data["humidity2"] = humidity2


            except Exception as e:

                print(
                    "Temperature Sensor Error:",
                    e
                )


        # =================================================
        # TWO GAS SENSORS
        # =================================================

        elif SENSOR_MODE == "two_gas":

            gas1 = (
                gas_sensor1.read_u16()
                * 3.3
                / 65535
            )

            gas2 = (
                gas_sensor2.read_u16()
                * 3.3
                / 65535
            )


            data["gas1"] = round(
                gas1,
                4
            )

            data["gas2"] = round(
                gas2,
                4
            )


        # =================================================
        # MQTT PUBLISH
        # =================================================

        client.publish(
            MQTT_TOPIC,
            json.dumps(data)
        )


        print("--------------------------------")
        print("Sent:", data)
        print("--------------------------------")


    except Exception as e:

        print(
            "Sender Error:",
            e
        )


        # ---------------------------------------------
        # MQTT RECONNECT
        # ---------------------------------------------

        try:
            client.disconnect()
        except:
            pass


        time.sleep(2)

        mqtt_connect()


    # =================================================
    # WAIT FOR NEXT TRANSMISSION
    # =================================================

    print(
        "Sleeping:",
        sleep_time,
        "seconds"
    )

    time.sleep(
        sleep_time
    )