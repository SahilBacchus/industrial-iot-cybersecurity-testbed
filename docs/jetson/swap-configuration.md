# Configure Swap on Jetson Nano

## 1. Check Existing Swap

Before making changes, verify your current memory and swap configuration:
```bash
free -h
sudo swapon --show
```

---

## 2. Create a 6 GB Swap File

Pre-allocate 6 GB of space for the swap file:
```bash
sudo fallocate -l 6G /mnt/swapfile
```

Restrict file permissions so only the root user can read or write to it:
```bash
sudo chmod 600 /mnt/swapfile
```

Set up the Linux swap area on the file:
```bash
sudo mkswap /mnt/swapfile
```

Enable the swap file immediately for the current session:
```bash
sudo swapon /mnt/swapfile
```
---

## 3. Enable Swap Permanently on Boot
 
Append the swap file configuration to your filesystem table (`/etc/fstab`) so it mounts automatically during system startup:

```bash
echo '/mnt/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## 4. Disable Default zram Swap

```bash
sudo systemctl disable nvzramconfig
```

---

## 5. Reboot & Verify

Reboot.
```bash
sudo reboot
```

Verify the swap is active.

```bash
free -h
sudo swapon --show
```