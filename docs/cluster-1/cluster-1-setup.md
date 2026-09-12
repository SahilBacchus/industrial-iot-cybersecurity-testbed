# Smart Grid Cluster-1 Setup and Execution Guide


## Overview & IP Assignment Table

| Device ID | IP Address | Sensor Type | Transmission Profile |
|---|---|---|---|
| **Pico 1** | 192.168.0.201 | Two temperature sensors | Fast |
| **Pico 2** | 192.168.0.202 | Two temperature sensors | Medium |
| **Pico 3** | 192.168.0.203 | Two temperature sensors | Slow |
| **Pico 4** | 192.168.0.204 | Two temperature sensors | Fast |
| **Pico 5** | 192.168.0.205 | Two temperature sensors | Medium |
| **Pico 6** | 192.168.0.206 | Two gas sensors | Slow |
| **Pico 7** | 192.168.0.207 | Two gas sensors | Fast |
| **Pico 8** | 192.168.0.208 | Two gas sensors | Medium |
| **Pico 9** | 192.168.0.209 | Two gas sensors | Slow |
| **Pico 10** | 192.168.0.210 | Two gas sensors | Medium |
| **Pico 11** | 192.168.0.211 | RFID | N/A |
| **Pico 12** | 192.168.0.212 | RFID | N/A |

### Network Settings

| Setting | Value |
|---|---|
| **Subnet Mask** | `255.255.255.0` (/24) |
| **Gateway** | `192.168.0.1` |

### Aggregator (Pi15)

| Interface | IP Address | Connection |
|---|---|---|
| **eth0** | `192.168.0.25` | Via switch |
| **wlan0** | — | Disconnected |

### Edge Server (Nano18)

| Interface | IP Address | Connection |
|---|---|---|
| **eth0** | `192.168.0.122` | Via switch |
| **wlan0** | — | Disconnected |

### Network Switch Connections

| Switch Port | Connected Device |
|---|---|
| **Port 1** | Router |
| **Port 2** | Aggregator (Pi15) |
| **Port 3** | Edge Server (Nano18) |

> [!NOTE]
> The Aggregator, Edge Server, and Router should be connected through the network switch. The switch configuration can be found in [`omada-switch-setup.md`](../omada-switch-setup.md).
>
> The complete IP address list for all devices can be found in [`device-list.md`](../device-list.md).



---

## Hardware Wiring & Configuration

The following tables define the wiring and pin assignments used for the sensor and RFID hardware connected to the Raspberry Pi Pico.

### Temperature Sensors

The DHT11/DHT22 temperature sensors are connected to the Raspberry Pi Pico using digital GPIO pins.

| Sensor | Pico GPIO | Physical Pin |
|---|---|---:|
| **Temperature Sensor 1** | `GP16` | `21` |
| **Temperature Sensor 2** | `GP17` | `22` |

### Gas Sensors

The MQ-series gas sensors use their analog output (AO), which is connected to the Pico's ADC inputs.

| Sensor | Output | Pico GPIO | ADC Channel | Physical Pin |
|---|---|---|---|---:|
| **Gas Sensor 1** | `AO` | `GP26` | `ADC0` | `31` |
| **Gas Sensor 2** | `AO` | `GP27` | `ADC1` | `32` |

### RFID Reader (MFRC522)

The MFRC522 RFID reader communicates with the Raspberry Pi Pico using SPI.

| MFRC522 Pin | Pico GPIO | Physical Pin |
|---|---|---:|
| **GND** | `GND` | `38` |
| **3.3V** | `3V3` | `36` |
| **SDA** | `GP5` | `7` |
| **SCK** | `GP6` | `9` |
| **MOSI** | `GP7` | `10` |
| **MISO** | `GP4` | `6` |
| **RST** | `GP22` | `29` |
| **IRQ** | — | — |

### Power Connections

The Pico power connections use the following rails:

| Pico Pin | Physical Pin | Connection |
|---|---:|---|
| **VSYS** | `39` | Positive (+) power rail |
| **GND** | `38` | Negative (-) power rail |

### Additional Information

The following resources provide additional information about the Raspberry Pi Pico pinout and the MFRC522 RFID module. They are provided as reference material and are not intended to define the complete hardware configuration above.

- [Raspberry Pi Pico W Pinout](https://picow.pinout.xyz/)
- [Using RFID Reader Module with Raspberry Pi Pico](https://how2electronics.com/using-rc522-rfid-reader-module-with-raspberry-pi-pico/)



---


## Required Code Configurations

### Required Files on Pico Nodes

Before powering on the Pico W nodes, transfer the necessary files to the device root using Thonny. Rename the main execution script to `main.py` so that MicroPython runs it automatically upon boot.

- **Sensor Nodes (Pico 1 – 10):**
  - `main.py` (renamed from `UoC_Cluster1_Sensors_Sender.py`)
  - `simple.py` (MicroPython MQTT library)

- **RFID Nodes (Pico 11 & 12):**
  - `main.py` (renamed from `UoC_Cluster1_RFID_Sender.py`)
  - `simple.py` (MicroPython MQTT library)
  - `mfrc522.py` (MFRC522 RFID driver library)

---

### Variable Classifications

**Global Settings (Same across all Pico nodes):**
- `SSID`: Wi-Fi network SSID
- `PASSWORD`: Wi-Fi network password
- `GATEWAY`: Gateway router IP address (`192.168.0.1`)
- `SUBNET_MASK`: Subnet mask (`255.255.255.0`)
- `DNS_SERVER`: DNS server IP address (`8.8.8.8`)
- `MQTT_BROKER`: Aggregator MQTT broker IP address (`192.168.0.25`)
- `CLUSTER_ID`: Cluster identifier (`"SG1"`)

**Node-Specific Settings (Must be updated per Pico):**
- `DEVICE_ID`: Unique node identifier string (e.g., `"pico_01"`)
- `STATIC_IP`: Static IP address assigned to the node
- `SENSOR_MODE`: Configuration type used on sensor nodes (`"two_temp"` or `"two_gas"`)
- `DEVICE_TYPE`: Fixed device identification type used on RFID nodes (`"rfid"`)
- `PROFILE`: Transmission timing profile (`"fast"`, `"medium"`, `"slow"`, or `N/A` for event-driven RFID)
- `READER_ID`: RFID reader identifier string (e.g., `"rfid_reader_01"`, used on RFID Picos)

---

### Node Configuration Summary Table

| Device | STATIC_IP | DEVICE_ID | SENSOR_MODE / DEVICE_TYPE | PROFILE | READER_ID |
|---|---|---|---|---|---|
| **Pico 1** | `192.168.0.201` | `"pico_01"` | `"two_temp"` | `"fast"` | — |
| **Pico 2** | `192.168.0.202` | `"pico_02"` | `"two_temp"` | `"medium"` | — |
| **Pico 3** | `192.168.0.203` | `"pico_03"` | `"two_temp"` | `"slow"` | — |
| **Pico 4** | `192.168.0.204` | `"pico_04"` | `"two_temp"` | `"fast"` | — |
| **Pico 5** | `192.168.0.205` | `"pico_05"` | `"two_temp"` | `"medium"` | — |
| **Pico 6** | `192.168.0.206` | `"pico_06"` | `"two_gas"` | `"slow"` | — |
| **Pico 7** | `192.168.0.207` | `"pico_07"` | `"two_gas"` | `"fast"` | — |
| **Pico 8** | `192.168.0.208` | `"pico_08"` | `"two_gas"` | `"medium"` | — |
| **Pico 9** | `192.168.0.209` | `"pico_09"` | `"two_gas"` | `"slow"` | — |
| **Pico 10** | `192.168.0.210` | `"pico_10"` | `"two_gas"` | `"medium"` | — |
| **Pico 11** | `192.168.0.211` | `"pico_11"` | `"rfid"` | N/A | `"rfid_reader_01"` |
| **Pico 12** | `192.168.0.212` | `"pico_12"` | `"rfid"` | N/A | `"rfid_reader_02"` |

## NTP Configuration

The Aggregator (`192.168.0.25`) should be configured as the local NTP server, acting as the local time reference for the smart grid devices. See [`ntp-server-setup.md`](../ntp-server-setup.md) for the complete NTP server installation and configuration.

The Jetson Nano uses Ubuntu's system time synchronization to sync with the local NTP server. Remeber to check [`ntp-server-setup.md`](../ntp-server-setup.md) to see how configure that.

The Pico W devices use MicroPython's `ntptime` module to synchronize their clocks and do not require an NTP server installation.

## Setup MQTT Broker on Aggregator

Install and enable Mosquitto on startup with the following: 
```bash
sudo apt update
sudo apt install -y mosquitto mosquitto-clients
sudo systemctl enable mosquitto
sudo systemctl start mosquitto
```

Create or edit the local broker configuration file to allow network connections from the Pico W nodes:
```bash
sudo nano /etc/mosquitto/conf.d/local.conf
```

Add the following configuration parameters:
```text
listener 1883
allow_anonymous true
```

Restart the Mosquitto service to apply the new configuration:
```bash
sudo systemctl restart mosquitto
```


## Startup Procedure

Follow the procedure below to bring Cluster 1 online.

### 1. Start the Aggregator

On the Aggregator Pi, navigate to the `cluster-1/aggregator/` directory and run:

```bash
python3 UoC_Cluster1_Aggregator.py
```

The Aggregator will begin receiving data from the Pico W devices.

### 2. Start the Edge Server

On the Jetson Nano Edge Server, navigate to the `cluster-1/edge/` directory and run both programs:

```bash
python3 UoC_Cluster1_Edgeserver.py
```
and in a seperate terminal window run:
```bash
sudo python3 UoC_Cluster1_Capture_Manager.py
```

The Edge Server will begin processing the data received from the Aggregator, while the Capture Manager automatically manages the network traffic capture.

### 3. Power On the Pico W Devices

Connect the Pico W devices to the USB hub and power them on.

The Pico W devices should already have their configured main.py files installed. Once powered on, each Pico W will automatically run `main.py` and begin transmitting data according to its configured transmission profile.

