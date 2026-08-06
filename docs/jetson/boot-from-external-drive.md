# Boot Jetson Nano from an External Drive

## Prerequisites

- External drive connected
- Root filesystem currently on `/dev/mmcblk0p1`
- Target partition available on external drive e.g. `/dev/mmcblk1p1`  

> [!WARNING]  
> This guide assumes your external drive is `/dev/mmcblk1` and the internal storage is `/dev/mmcblk0`. Always verify your specific device identifiers using the lsblk command before proceeding to avoid data loss.

---

## 1. Format the External Partition

Unmount the partition if necessary.

```bash
sudo umount /dev/mmcblk1p1
```

Create an ext4 filesystem.

```bash
sudo mkfs.ext4 /dev/mmcblk1p1
```

---

## 2. Copy the Existing System

Mount the new partition.

```bash
sudo mount /dev/mmcblk1p1 /mnt
```

Copy the complete filesystem.

```bash
sudo cp -ax / /mnt
```

Unmount when finished.

```bash
sudo umount /mnt
```

---

## 3. Update Boot Configuration

Open the boot configuration.

```bash
sudo nano /boot/extlinux/extlinux.conf
```

Locate the active `APPEND` line.

Replace

```
root=/dev/mmcblk0p1
```

with

```
root=/dev/mmcblk1p1
```

Save the file.

---

## 4. Reboot

```bash
sudo reboot
```

---

## 5. Verify

Confirm the root filesystem is now using the external drive.

```bash
df -h /
```