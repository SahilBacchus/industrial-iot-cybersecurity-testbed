# NTP Time Synchronization Setup: Raspberry Pi & Jetson Nano

This guide outlines the steps to install and configure a Raspberry Pi as a local Network Time Protocol (NTP) server using `chrony`, and configure a Jetson Nano client running Ubuntu (`systemd-timesyncd`) to sync its system clock accordingly.

The aggregator Raspberry Pi functions as the central local NTP server for the entire testbed subnet (`192.168.0.0/24`). This ensures that both the edge server (Jetson Nano) and edge sensors (Raspberry Pi Pico W nodes) share a synchronized timeline

## Step 1: Install Chrony on the Aggregator Raspberry Pi 

Update package lists and install the `chrony` NTP service on the Raspberry Pi.

Update package lists:
```bash
sudo apt update
```
Install chrony:

```bash
sudo apt install chrony -y
```
Enable and start the service at startup:

```bash
sudo systemctl enable chrony
sudo systemctl start chrony
```
## Step 2: Configure the Raspberry Pi as a Local NTP Server

Update the `chrony` configuration to accept time synchronization requests from your local subnet and allow offline local timekeeping.

Open the configuration file on your Raspberry Pi:

```bash
sudo nano /etc/chrony/chrony.conf
```
Add the allow rule and local stratum setting:

```text
allow 192.168.0.0/24
local stratum 10
```

The allow rule permits devices on your local subnet to use the aggregator as their NTP server. The local configuration allows the aggregator to provide local time when the network is isolated from the internet.

> [!NOTE]
> Adjust the subnet prefix to match your specific local network configuration.

Save the file and restart chrony to apply the changes:

```bash
sudo systemctl restart chrony
```
Verify server synchronization and sources:

```bash
chronyc tracking
chronyc sources -v
```

## Step 3: Configure the Jetson Nano

Configure Ubuntu's default systemd-timesyncd service on the Jetson Nano to point directly to the Raspberry Pi NTP server.

Open the time configuration file on the Nano:

```bash
sudo nano /etc/systemd/timesyncd.conf
```
Find the line starting with #NTP= and change it to point to your Raspberry Pi's static local IP address:

```text
NTP=192.168.0.25
```
> [!NOTE]
> Replace 192.168.0.25 with the actual static IP address of your Raspberry Pi.

Save the file and restart the time synchronization service:

```bash
sudo systemctl restart systemd-timesyncd
```

## Step 4: Verify the Connection

Verify that the Jetson Nano has successfully established contact with the Raspberry Pi server.

Run the status command on the Jetson Nano:

```bash
timedatectl status
```

Check for the following confirmation parameters:

System clock synchronized: yes

NTP service: active

To inspect the active server IP address in detail, run:

```bash
timedatectl timesync-status
```