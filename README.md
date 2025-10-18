# PocketDigi

Turn your Android phone and a Bluetooth TNC into a powerful, portable APRS Digipeater and bi-directional iGate.

# What It Does

PocketDigi is a mobile application designed for amateur radio operators. It connects to a standard KISS-enabled Bluetooth TNC (like a Mobilinkd TNC3 or similar device) and uses your phone's internet and GPS to provide APRS services wherever you are. Leave it running in your vehicle or at a temporary location to instantly enhance the local APRS network.

# Key Features

- **Bluetooth KISS Connectivity:** Wirelessly connect to your TNC without cumbersome cables.

- **Smart APRS Digipeater:** Intelligently re-transmits packets according to the New-N Paradigm (WIDE1-1, WIDE2-n), avoiding unnecessary packet storms.

- **Bi-Directional iGate:** Gates local RF traffic to the APRS-IS network (internet) and gates internet traffic for your local area back out to RF.

- **Automatic GPS Beacons:** Uses your phone's GPS to periodically beacon your station's position on both RF and APRS-IS, identifying it as an active iGate and digipeater.

- **Real-Time Monitoring:** View live RF and internet traffic in a color-coded activity log and see your station's performance with at-a-glance statistics.

- **Set and Forget:** Your callsign is saved automatically, so you only need to enter it once.

# How to Use PocketDigi

Using the app is designed to be simple. Follow these steps to get on the air.

## Step 1: Pair Your TNC

Before opening PocketDigi, go to your phone's Bluetooth Settings. Scan for devices and pair your KISS TNC just like you would with a pair of headphones. This only needs to be done once.

## Step 2: Set Your Callsign

1. Open the PocketDigi app.
2. In the Operation card, tap the **Callsign-SSID** field.
3. Enter your amateur radio callsign. If you are using an SSID, add it with a dash (e.g., `N0CALL-7`).
4. Your callsign is saved automatically for the next time you open the app.

## Step 3: Connect to the TNC

1. In the Bluetooth TNC card, tap the dropdown menu (**Select a Paired TNC**).
2. Choose your TNC from the list of paired devices.
3. Press the blue **Connect** button.
4. The status indicator will turn green, and the button will change to a red **Disconnect** button. Your beaconing will start automatically.

## Step 4: Configure Your Station

You can enable or disable the main functions using the switches in the Operation card:

- **Enable Digipeater:** This is on by default. When enabled, your station will listen for packets that need re-transmission and send them back out on RF.

- **Enable iGate:** When enabled, your station will:
  - Gate heard RF packets to the internet.
  - Gate local packets from the internet to RF.

> **Note:** You must have an internet connection and have granted the app location permissions for this to work. You can only toggle this switch before you connect to the TNC.

## Step 5: Monitor Activity

Once connected, you can monitor everything your station is doing.

- **Statistics:** The counters at the top will show you how many packets you have heard, digipeated, gated to/from the internet, and beaconed.

- **Activity Log:** The log at the bottom shows every packet in real-time.

  - <span style="color:lightgreen">Green (RX)</span>: Packets heard directly over the radio.  
  - <span style="color:yellow">Yellow (TX)</span>: Packets you digipeated.  
  - <span style="color:cyan">Cyan (TX)</span>: Packets you gated from the internet to the radio.  
  - <span style="color:orange">Orange (TX)</span>: Your own position beacons.  
  - White: System messages (e.g., "Connected," "Disconnected").
