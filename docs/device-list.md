# Device List

## NVIDIA Jetson Devices

| Device No. | Model  | IP Type | IP Address | Notes |
| :--- | :--- | :--- |  :--- | :--- |
| **17** | Jetson Nano | Static | 192.168.0.121/24 | |
| **18** | Jetson Nano | Static | 192.168.0.122/24 | |

## Raspberry Pi Devices

| Device No. | Model | IP Type | IP Address | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **15** | Raspberry Pi 4 Model B | Static | 192.168.0.25/32 | |
| **14** | Raspberry Pi 4 Model B | Static | 192.168.0.24/32 | |
| **14 (Duplicate)** | Raspberry Pi 4 Model B | Unknown | Unknown | No boot, no display, missing SD card (unflashed). Placed in box. |
| **13** | Raspberry Pi 5 | Static | 192.168.0.23/24 | |
| **12** | Raspberry Pi 4 Model B | Static | 192.168.0.22/32 | |
| **11** | Raspberry Pi 4 Model B | Static | 192.168.0.21/32 | |
| **10** | Raspberry Pi 4 Model B | Static | 192.168.0.20/24 | |
| **9** | Raspberry Pi 5 | Static | 192.168.0.19/24 | |
| **8** | Raspberry Pi 4 Model B | Static | 192.168.0.18/24 | |
| **7** | Raspberry Pi 5 | Static | 192.168.0.17/24 | Housed in mini-PC style enclosure. |
| **6** | Raspberry Pi 5 | Static | 192.168.0.16/24 | Housed in mini-PC style enclosure. |
| **5** | Raspberry Pi 5 | Static | 192.168.0.15/24 | |
| **4** | Raspberry Pi 4 Model B | Static | 192.168.0.14/24 | |
| **3** | Raspberry Pi 5 | Static | 192.168.0.13/24 | |
| **2** | Raspberry Pi 4 Model B | Static | 192.168.0.12/24 | One USB 2.0 port is physically damaged. |
| **Unmarked** | Raspberry Pi 4 Model B | Unknown | Unknown | Raspberry Pi OS is not flashed yet. |

***

### Overall Notes
- **Subnet Mismatch**: Devices 11, 12, 14, and 15 use a `/32` subnet mask, while the others use `/24`.


## Raspberry Pi Pico W Devices

| Device No. | Model | IP Type | IP Address | Notes |
| :--------- | :---------------- | :------ | :--------------- | :---- |
| **1** | Raspberry Pi Pico W | Static | `192.168.0.201` | |
| **2** | Raspberry Pi Pico W | Static | `192.168.0.202` | |
| **3** | Raspberry Pi Pico W | Static | `192.168.0.203` | |
| **4** | Raspberry Pi Pico W | Static | `192.168.0.204` | |
| **5** | Raspberry Pi Pico W | Static | `192.168.0.205` | |
| **6** | Raspberry Pi Pico W | Static | `192.168.0.206` | |
| **7** | Raspberry Pi Pico W | Static | `192.168.0.207` | |
| **8** | Raspberry Pi Pico W | Static | `192.168.0.208` | |
| **9** | Raspberry Pi Pico W | Static | `192.168.0.209` | |
| **10** | Raspberry Pi Pico W | Static | `192.168.0.210` | |
| **11** | Raspberry Pi Pico W | Static | `192.168.0.211` | |
| **12** | Raspberry Pi Pico W | Static | `192.168.0.212` | |
| **13** | Raspberry Pi Pico W | Static | `192.168.0.213` | |
| **14** | Raspberry Pi Pico W | Static | `192.168.0.214` | |
| **15** | Raspberry Pi Pico W | Static | `192.168.0.215` | |
| **16** | Raspberry Pi Pico W | Static | `192.168.0.216` | |
| **17** | Raspberry Pi Pico W | Static | `192.168.0.217` | |
| **18** | Raspberry Pi Pico W | Static | `192.168.0.218` | |
| **19** | Raspberry Pi Pico W | Static | `192.168.0.219` | |
| **20** | Raspberry Pi Pico W | Static | `192.168.0.220` | |
| **21** | Raspberry Pi Pico W | Static | `192.168.0.221` | |
| **22** | Raspberry Pi Pico W | Static | `192.168.0.222` | |
| **23** | Raspberry Pi Pico W | Static | `192.168.0.223` | |
| **24** | Raspberry Pi Pico W | Static | `192.168.0.224` | |
| **25** | Raspberry Pi Pico W | Static | `192.168.0.225` | |
| **26** | Raspberry Pi Pico W | Static | `192.168.0.226` | |
| **27** | Raspberry Pi Pico W | Static | `192.168.0.227` | |
| **28** | Raspberry Pi Pico W | Static | `192.168.0.228` | |

> **IP Assignment Note:** The Raspberry Pi Pico W devices receive consistent IP addresses through **DHCP reservations configured on the testbed router**. Addresses are assigned sequentially within the range `192.168.0.201`–`192.168.0.228`, with each device receiving a unique address following the convention **`192.168.0.(200 + device number)`**. For example, Device 1 is assigned `192.168.0.201`, Device 2 is assigned `192.168.0.202`, and Device 28 is assigned `192.168.0.228`.
