<p align="center">
  <img src="assets/touchstage_icon.png" width="120" height="120" alt="TouchStage Icon" style="border-radius: 26px;">
</p>

<h1 align="center">TouchStage</h1>

<p align="center">
  <b>High-Performance Wireless MIDI Suite for Live Performance & Studio Control</b><br>
  Zero-latency wireless MIDI streaming between mobile devices and macOS via native CoreMIDI.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Android-black?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/MIDI-Native%20CoreMIDI-007AFF?style=flat-square" alt="CoreMIDI">
  <img src="https://img.shields.io/badge/Latency-%3C%201ms%20Binary%20UDP-00C7BE?style=flat-square" alt="Latency">
  <img src="https://img.shields.io/badge/Architecture-100%25%20Native-34C759?style=flat-square" alt="Native">
</p>

---

## Overview

**TouchStage** transforms your mobile devices into ultra-responsive, modular MIDI control surfaces for your digital audio workstation (DAW). Built entirely with native code on both platforms (Objective-C/Cocoa on macOS and Java/Canvas on Android), it delivers sub-millisecond tactile response, zero webview overhead, and seamless plug-and-play operation.

<br>

<table align="center" width="100%">
  <tr>
    <td align="center" width="33%">
      <h3>⚡ Real-Time Response</h3>
      <p>3-byte binary datagrams streamed over low-overhead UDP for imperceptible latency during live playing.</p>
    </td>
    <td align="center" width="33%">
      <h3>📱 Multi-Device Mesh</h3>
      <p>Connect multiple phones and tablets simultaneously — use one device for faders and another for drum pads.</p>
    </td>
    <td align="center" width="33%">
      <h3>🔌 Zero Drivers Required</h3>
      <p>Creates a native macOS CoreMIDI virtual port visible instantly to any music production software.</p>
    </td>
  </tr>
</table>

---

## The TouchStage Ecosystem

The suite consists of three tightly integrated components:

### 1. TouchStage Bridge (macOS Menu Bar)
A lightweight background daemon that resides in your macOS menu bar.
* **Native Virtual MIDI Port:** Exposes `TouchStage Controller` directly to the macOS audio subsystem.
* **Auto-Discovery Beacon:** Broadcasts discovery beacons via UDP (port 9002) so mobile devices connect automatically without typing IP addresses.
* **Adaptive Status Monitor:** Dynamically resizes to display connected devices, active IP endpoints, and port health.
* **One-Click Quick Copy:** Copy network endpoint info to clipboard instantly.

```bash
./run_bridge.sh
```

### 2. TouchStage Studio (macOS Layout Editor)
A standalone desktop designer for building custom MIDI controller layouts.
* **Visual Canvas:** Right-click anywhere to add faders, rotary knobs, momentary/toggle pads, XY pads, and labels.
* **Precision Inspector:** Configure MIDI channels (1–16), CC/Note numbers, min/max values, custom colors, and dimensions.
* **Instant Device Sync:** Broadcast active templates over TCP directly to all connected devices in real time.

```bash
./run_editor.sh
```

### 3. TouchStage Controller (Android App)
The performance instrument running on phone or tablet hardware.
* **Hardware-Accelerated Surface:** Custom 2D rendering pipeline tuned for 60/120 FPS multitouch interaction.
* **Distraction-Free Interface:** Edge-to-edge layout calibrated to your screen dimensions.
* **Instant Preset Switching:** Built-in templates including **Stage 6-Track**, **Live Mixer 8CH**, and **16-Pad Matrix**.
* **Zero Configuration:** Automatically scans the local Wi-Fi network and pairs with your Mac in seconds.

---

## Quick Start

### 1. Launch the macOS Bridge
Clone the repository and launch the bridge daemon:
```bash
./run_bridge.sh
```
The TouchStage icon will appear in your macOS menu bar.

### 2. Connect Your Mobile Device
1. Install and open **TouchStage** on your Android device (using the included `TouchStage.apk` or building from source).
2. Ensure both your Mac and phone are on the same Wi-Fi network.
3. The app will automatically discover your computer — tap to connect.

### 3. Enable in Your DAW
1. Open your DAW's MIDI Preferences:
   * **Ableton Live:** `Preferences` &rarr; `Link / MIDI` &rarr; Enable **Track** and **Remote** for `TouchStage Controller`.
   * **Logic Pro / MainStage:** `Settings` &rarr; `MIDI` &rarr; `Inputs` &rarr; Check `TouchStage Controller`.
   * **Reaper / Pro Tools / FL Studio:** Enable `TouchStage Controller` as an active MIDI input device.
2. Touch any fader or pad on your phone — the MIDI signal is registered immediately.

---

## DAW Compatibility

TouchStage utilizes standard system-level MIDI endpoints and is fully compatible with any software supporting MIDI input:

| DAW / Host | Status | Transport | CC / Notes | Pitch & Mod |
| :--- | :---: | :---: | :---: | :---: |
| **Ableton Live (10 / 11 / 12)** | Supported | Yes | Yes | Yes |
| **Apple Logic Pro & MainStage** | Supported | Yes | Yes | Yes |
| **Cockos Reaper** | Supported | Yes | Yes | Yes |
| **Avid Pro Tools** | Supported | Yes | Yes | Yes |
| **Image-Line FL Studio** | Supported | Yes | Yes | Yes |
| **Bitwig Studio** | Supported | Yes | Yes | Yes |
| **Studio One** | Supported | Yes | Yes | Yes |

---

## Technical Architecture

```
┌────────────────────────────────────────────────────────┐
│                   Android Devices                      │
│   TouchStage App (MidiSurfaceView • Hardware Canvas)   │
└───────────────────────────┬────────────────────────────┘
                            │
               Binary UDP   │   JSON TCP
               Port 9001    │   Port 9000
                            ▼
┌────────────────────────────────────────────────────────┐
│             TouchStage Bridge (macOS Daemon)           │
│        Auto-Discovery Beacon (UDP Port 9002)           │
└───────────────────────────┬────────────────────────────┘
                            │
                     Apple CoreMIDI
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│                Digital Audio Workstation               │
│        (Ableton Live • Logic Pro • Reaper • etc.)       │
└────────────────────────────────────────────────────────┘
```

* **High-Speed MIDI Protocol:** Datagrams are transmitted as raw 3-byte packets `[status, cc_number, value]`, avoiding string serialization overhead.
* **Auto-Discovery:** Uses UDP multicast/broadcast announcements (`_touchstage._tcp`) on port 9002 for instantaneous zero-touch pairing.
* **Layout Serialization:** Layouts and control hierarchies are stored in clean, portable JSON format (`layouts/*.json`).

---

## Building from Source

### macOS Apps
Requires macOS with Xcode Command Line Tools installed (`clang`):
```bash
# Build both Bridge and Editor
./macos/build_all.sh

# Or build individual components
./macos/bridge/build_bridge.sh
./macos/editor/build_editor.sh
```

### Android App
Requires Android SDK or Android Studio:
```bash
cd android
./gradlew assembleDebug
```
The generated APK will be located at `android/app/build/outputs/apk/debug/app-debug.apk`.

---

## License

This project is open-source and available under the [MIT License](LICENSE).
