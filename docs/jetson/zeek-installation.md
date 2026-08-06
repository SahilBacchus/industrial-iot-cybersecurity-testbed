# Zeek Installation via Docker

The native Ubuntu installation did not on the Jetson Nano as Ubuntu 18.04 is no longer supported by OpenSUSE Build Service repo for Zeek, so Zeek was installed using the official Docker image.

---

## 1. Confgure Docker Permissions

Add current user to Docker group to run containers without `sudo`:
```bash
sudo usermod -aG docker $USER
```

Apply the new group membership to your current terminal session immediately:
```bash
newgrp docker
```

---

## 2. Pull the Zeek Image

Download the official Zeek Long-Term Support image from Docker Hub:
```bash
docker pull zeek/zeek:lts
```

---

## 3. Create Configuration Directories

```bash
mkdir -p ~/zeek-config ~/zeek-logs
```

---

## 4. Create Custom Logging Configuration

Create a configuration file to control how Zeek handles and stores its generated logs:
```text
~/zeek-config/custom_logging.zeek
```

Paste the following policy script into the file, then save and exit:
```zeek
@load base/frameworks/logging

redef Log::default_rotation_interval = 1min;

redef Log::default_logdir = "/zeek-logs";
```

---

## 5. Create the Wrapper Script

Creating a wrapper script allows you to run the Dockerized container seamlessly by just typing `zeek` in your terminal.

Open a new system binary file:
```bash
sudo nano /usr/local/bin/zeek
```

Paste the following script, then save and exit: 

> [!NOTE]
> If using Ethernet instead of Wi-Fi, replace: `-i wlan0` with `-i eth0`
```bash
#!/bin/bash

HOST_CONFIG="$HOME/zeek-config"
HOST_LOGS="$HOME/zeek-logs"

docker run -it --rm \
  --net=host \
  --privileged \
  -v "$HOST_CONFIG":/zeek-config \
  -v "$HOST_LOGS":/zeek-logs \
  zeek/zeek:lts \
  zeek -i wlan0 /zeek-config/custom_logging.zeek
```

Make it executable:
```bash
sudo chmod +x /usr/local/bin/zeek
```

---

## 6. Run Zeek & Generate Traffic

Launch the network monitoring instance:

```bash
zeek
```

> [!NOTE]
> Leave this terminal window running. Open a new terminal window or browser to generate network traffic (e.g., browse web pages or run ping google.com).

Stop Zeek with:

```
Ctrl+C
```

---

## 7. Verify Network Logs

Navigate to your local log storage directory to inspect the generated network traffic analysis files:
```bash
cd ~/zeek-logs
ls -R
```

Expect to find a variety of log files, including `conn.log`, `http.log`, and `dns.log`, which contain detailed records of network connections, HTTP requests, and DNS queries, respectively.
