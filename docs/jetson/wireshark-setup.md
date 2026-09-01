# Wireshark & Dumpcap Capture Setup

Configuring dumpcap on Ubuntu to allow non-root users to capture packets and save rotating PCAP files directly to the home directory.

## Prerequisite
Ensure `wireshark-common` and `dumpcap` are installed on your system.

## 1. Configure User Group & SUID Permissions
Add your user to the `wireshark` group to authorize packet-capturing capabilities:

```bash
sudo usermod -aG wireshark $USER
```

Apply SUID permissions to the `dumpcap` binary so it retains file-writing access even after dropping live packet-capture privileges:

```bash
sudo chown root:wireshark /usr/bin/dumpcap
sudo chmod 4755 /usr/bin/dumpcap
```
> [!NOTE]
> You may need to reboot for the group changes to take full effect.

## 2. Navigate to the Script Directory
Change your current working directory to where the capture script is located within the repository:

```bash
cd jetson/wireshark/
```

## 3. Review and Configure the Script
The automated capture script [capture.sh](/jetson/wireshark/capture.sh) automatically creates and configures the output directory at `~/pcap_captures`. If you wish to change where the capture files are saved, open the script and modify the `OUTPUT_DIR` variable:

```bash
nano capture.sh
```

## 4. Run the Capture Script
Make the script executable and run it by passing your target network interface (e.g., `eth0`):

```bash
chmod +x capture.sh
./capture.sh eth0
```
> [!NOTE]
> If you are unsure which interface to monitor, run `ip -o link show` to list all available network links.

Stop the capture instance anytime with:

```text
Ctrl+C
```

## 5. Verify Captured Files
Navigate to your local capture storage directory to inspect the generated rotating PCAP files:

```bash
cd ~/pcap_captures
ls -R
```