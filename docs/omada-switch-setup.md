# Omada Network Switch Setup: Port Mirroring Configuration

This guide outlines the steps to configure port mirroring on an Omada network switch (ES208G) to mirror traffic from the router and aggregator to an edge server for network analysis.

## Network Topology Overview

| Port | Connected Device |
| :--- | :--- |
| **Port 1** | Router |
| **Port 2** | Aggregator |
| **Port 3** | Edge Server |

> [!NOTE]
> The following configuration sets up **Port 1** (Router) and **Port 2** (Aggregator) as mirrored source ports, capturing both incoming (ingress) and outgoing (egress) traffic and sending it to **Port 3** (Edge Server) for network analysis.


---

## Step 1: Access the Omada Switch Management Interface

Open a web browser and log into the switch management dashboard by navigating to its default IP address:

```text
http://192.168.0.100

```

> [!NOTE]
> `192.168.0.100` is normally the default IP address to connect to the switch as it usually connects to the router first. If it does not load, check your router's attached client list or DHCP lease table to find the actual assigned IP address of the switch.

---

## Step 2: Navigate to Port Mirroring Settings

Once logged into the dashboard, browse to the mirroring configuration section (**Monitoring > Mirroring**).


---

## Step 3: Configure Session and Mirroring Port

In the first configuration table, set up the global session target:

* Set **Session 1** status to **Enable**
* Set the **Mirroring Port** to **Port 3** (Edge Server)

---

## Step 4: Select Mirrored Source Ports

In the second configuration table, specify the traffic sources to be monitored:

* Select **1** for the Session
* Select **Ports 1 and 2** (Router and Aggregator) for the **Mirrored Port**
* Enable both **Ingress** and **Egress** traffic capture options

---

## Step 5: Apply and Save Configuration

Save your settings to ensure they persist across reboots:

1. Click the **Apply** button at the bottom of the configuration section.
2. Click the **Save** button in the top right corner of the web interface.