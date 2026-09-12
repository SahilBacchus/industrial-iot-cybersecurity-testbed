# Cluster-1 Quickstart Guide

Quick execution guide for starting remote cluster jobs (`start_cluster.sh`) and retrieving testbed log data (`download_cluster_data.sh`).

**Cluster Nodes:**

* **Aggregator Node (`pi15`):** `192.168.0.25`
* **Edge Server Node (`nano18`):** `192.168.0.122`

> ### Prerequisites:
> 
> 
> * **Directory:** Open your terminal and navigate to the folder containing the scripts (e.g., `cd cluster-1`) before running commands.
> * **Terminal:** Windows users must run `.sh` scripts using Git Bash, WSL, or another Unix-like terminal.
> * **Power:** Ensure all nodes are powered on and connected, including the Aggregator (`pi15`), Edge Server (`nano18`), and Pico W devices.
> * **Network:** Connect the Aggregator and Edge Server to the network switch via Ethernet (`eth0`). The control machine must be on the same local network.
> * **Credentials:** SSH and sudo credentials for the nodes will be required during script execution.
> 
> 

---

## 1. Make Scripts Executable

Run once locally to set execution permissions:

```bash
chmod +x start_cluster.sh download_cluster_data.sh

```

---

## 2. Start Cluster (`./start_cluster.sh`)

Launches remote processes across `pi15` and `nano18` in sequence.

```bash
./start_cluster.sh

```

### Execution Options & Prompts

1. **Start Confirmation**
* **Prompt:** `Do you want to start the entire cluster now? (y/n):`
* **Input:** `y` to launch, `n` to abort.


2. **Test Duration**
* **Prompt:** `Enter test duration in minutes (or type 0 for indefinite run):`
* **Timed Run (`> 0`):** Services run via `timeout` wrappers and automatically stop when finished. Safe to disconnect your terminal after launching.


* **Indefinite Run (`0`):** Services run in the background indefinitely. Press `Ctrl+C` in the terminal to abort and shut down all nodes remotely.





> [!NOTE]
> **Configuring `start_cluster.sh`**
> 
> Before running, verify or adjust the following variables under the **CONFIG** section inside `start_cluster.sh`:
>
> * `DEV1_USER` & `DEV1_IP`: Edge Server SSH username (`nano18`) and IP address (`192.168.0.122`). 
> * `EDGE_DIR`: Path to the edge project directory on the Edge Server. 
> * `DEV2_USER` & `DEV2_IP`: Aggregator SSH username (`pi15`) and IP address (`192.168.0.25`).
> * `AGG_DIR`: Path to the aggregator project directory on the Aggregator node.
> * `SUDO_PASS`: Leave as `""` to enter your sudo password interactively at runtime.


---

## 3. Download Log Data (`./download_cluster_data.sh`)

Retrieves remote testbed log files to your local host via `scp`.

```bash
./download_cluster_data.sh

```

### Device Selection Prompt

**Prompt:** `Which device do you want to pull data from?`

* **`1` (nano18):** Downloads Edge Server logs from `192.168.0.122`.


* **`2` (pi15):** Downloads Aggregator data from `192.168.0.25`.


* **`3` (Both):** Downloads logs sequentially from both nodes.



Logs are saved locally to a timestamped folder inside your `Downloads` directory.

> [!NOTE]
> **Configuring `download_cluster_data.sh`**
> 
> Check or modify the following variables in the **CONFIG** section inside `download_cluster_data.sh`:
>
> * `BASE_LOCAL_DIR`: Local folder where logs are downloaded (defaults to `/c/Users/${USERNAME}/Downloads`).
> * `DEV1_USER` / `DEV1_IP` & `DEV1_PATHS`: Username, IP (`192.168.0.122`), and array of remote directory paths to pull from the Edge Server.
> * `DEV2_USER` / `DEV2_IP` & `DEV2_PATHS`: Username, IP (`192.168.0.25`), and array of remote directory paths to pull from the Aggregator node.
