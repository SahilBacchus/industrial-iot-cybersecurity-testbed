# Setup and Control Tuya Smart Bulb via Python

This guide covers pairing Tuya smart bulbs, configuring a developer account to retrieve local API keys, and testing local control via Python using TinyTuya.

Remember to check out https://github.com/jasonacox/tinytuya for more information.

## Prerequisites

- Install the `tinytuya` library via pip:
```bash
pip install tinytuya
```

## 1. Setup Bulb and Wi-Fi Connection

- Turn the bulb on and off quickly **4 times** to put it into pairing mode, it will flash red if done correctly.
- Add the bulb to the Tuya app under the router Wi-Fi. 
> [!NOTE]
> For the subsequent steps to work, the router must be momentarily connected to the internet, or you can create a mobile hotspot with the same name and password as the router on a separate device.

---

## 2. Create a Tuya Developer Account

- Go to [iot.tuya.com](https://iot.tuya.com) to create a developer Tuya account.
- When it asks for the account type, you can click **"Skip this step"**.
- On the left-hand side, click the **Cloud icon > Project Management**.
- Click the **Create Cloud Project** button.
- Fill out details like Project Name, and for the data center select **"Western American Data Center"** as this corresponds to the `us` Region used later during the tinytuya wizard setup.
- Enter the project, go to **Devices > Link App Account**, press the **Add App Account** button, and follow the steps and QR code to link the Tuya app with your developer account (reference guide available [here](https://developer.tuya.com/en/docs/iot/link-devices?id=Ka471nu1sfmkl#title-8-Procedure)).

---

## 3. Generate Local Keys

> [!NOTE]
> All local keys can be retrieved after setting up just one bulb, but you may still need to run each bulb through the wizard individually for them to properly work.

- If the app was linked correctly, the **Devices > All Devices** tab should display a list of all devices and their corresponding **Device ID** (note these down for the next steps).
- Within the **Overview** tab, find your **Access ID / Client ID** (corresponds to API Key) and **Access Secret / Client Secret** (corresponds to Secret).
- After installing `tinytuya`, run the following command:
```bash
  python -m tinytuya wizard
```
- Enter your credentials when prompted (API Key, API Secret, Device ID, Region).
- Check tuya-raw.json, press Ctrl+F, and search for local_key. There should be one for each linked device (check the name field as well to easily identify them).
- Run the following command to get the version number, IP address, and MAC address if you want to make it static later via the router configuration:  
```bash
  python -m tinytuya scan
```

---

## 4. Test Control via Python

You can now turn off your phone hotspot or remove internet access from the router to verify the local setup is functioning.

```python
import tinytuya

bulb = tinytuya.BulbDevice(
    dev_id='your-device-id-here',
    address='Auto',  # Quick testing; for actual IP, find from 'tinytuya scan'
    local_key='your-local-key-here',
    version=3.5 
)

bulb.turn_off()

# Turn the bulb ON
print("Turning bulb on...")
bulb.turn_on()

# Set color to Red (RGB values range from 0-255)
print("Changing color to red...")
bulb.set_colour(255, 0, 0)
```