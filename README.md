# TouchStage Suite - Native Architecture & Apple-like Minimalism

TouchStage is a professional wireless MIDI ecosystem featuring **100% native applications** on macOS and Android, designed with **Apple-like minimalism**, zero webviews, clean typography, and zero emoji clutter.

---

## Architecture Overview

```
MIDI Controller/
├── assets/
│   └── touchstage_icon.png      # Master High-Res TouchStage Icon
├── macos/
│   ├── bridge/
│   │   ├── TouchStage Bridge.app # macOS Menu Bar daemon (CoreMIDI Virtual Source & Multi-device Wi-Fi Hub)
│   │   └── build_bridge.sh
│   ├── editor/
│   │   ├── TouchStage Studio.app # Dedicated macOS Layout Editor with right-click canvas menu
│   │   └── build_editor.sh
│   └── build_all.sh             # Compiles both macOS apps
├── android/
│   ├── app/src/main/
│   │   ├── AndroidManifest.xml
│   │   ├── res/mipmap-*/        # TouchStage High-Res App Launcher Icons
│   │   └── java/com/airmidi/controller/
│   │       ├── MainActivity.java        # Immersive native activity (edge-to-edge camera cutout)
│   │       ├── MidiSurfaceView.java     # Hardware-accelerated 2D Canvas & minimalist corner status
│   │       ├── NetworkDiscovery.java    # Auto-discovers Mac Bridge via UDP beacons (Zero IP typing)
│   │       ├── SettingsModal.java       # iOS-style dark settings sheet (Discovered Bridges & Presets)
│   │       ├── MidiNetworkManager.java  # Sub-millisecond binary MIDI socket (UDP/TCP)
│   │       └── LayoutModel.java
│   └── build.gradle
├── TouchStage.apk               # Android Native App Package
├── run_bridge.sh                # Starts TouchStage Bridge
├── run_editor.sh                # Opens TouchStage Studio
└── layouts/
    ├── reference_preset.json    # Stage 6-Track (Reference Rig)
    ├── live_mixer_8ch.json      # Live Mixer 8CH
    └── drum_pad_matrix.json     # 16-Pad Performance
```

---

## 1. macOS: Two Dedicated Applications

### App 1: TouchStage Bridge (`TouchStage Bridge.app`)
- **Menu Bar Daemon**: Runs silently in the macOS status bar with a minimalist monochrome slider icon.
- **Virtual CoreMIDI Port**: Instantly exposes `TouchStage Controller` to Ableton Live, Logic Pro, MainStage, Reaper, and Pro Tools.
- **Multi-Device Support**: Connect multiple phones simultaneously (e.g., Phone 1 as faders, Phone 2 as synth/drums).
- **Auto-Discovery Beacon**: Automatically broadcasts its presence (`_touchstage._tcp` and UDP port 9002) so phones detect it immediately without manual IP configuration.

Launch with:
```bash
./run_bridge.sh
```

### App 2: TouchStage Studio (`TouchStage Studio.app`)
- **Standalone Layout Editor**: Dedicated native desktop app for designing controller rigs.
- **Right-Click Canvas Menu**: Right-click anywhere on the black canvas to add:
  - Vertical Fader
  - Rotary Knob
  - Push Button / Pad
  - XY Pad
  - Text Label
- **Inspector Panel**: Clean Apple-style controls for MIDI channel (1-16), CC/Note number, range, native Apple color well, and geometry.
- **Sync to Devices**: Pushes the active layout directly to all connected phones via the local bridge.

Launch with:
```bash
./run_editor.sh
```

---

## 2. Android: Minimalist Performance Instrument

- **Zero Clutter**: The layout fits the exact aspect ratio of the phone screen with zero scrolling, edge-to-edge camera cutout support, and full screen immersion.
- **Corner Status Indicator**:
  - Located in the top-right corner.
  - Minimalist LED dot: Green (Connected), Amber (Connecting), Grey (Offline).
  - Minimalist icon opens the Settings sheet.
- **Zero IP Typing (Auto-Discovery)**:
  - Automatically discovers your Mac on Wi-Fi (e.g., "Samys's iMac").
  - Tap the discovered computer to connect instantly.
- **Settings Sheet**:
  - Available Bridges (tap to connect).
  - Presets: Stage 6-Track (Reference), Live Mixer 8CH, 16-Pad Matrix.
  - Device Identity: Name your phone (e.g., "Phone 1", "Tablet").
- **Ultra-low Latency**: Sends 3-byte binary MIDI datagrams (`[status, cc, value]`) over UDP with sub-millisecond response.

---

## 3. DAW Setup (Ableton Live, Logic Pro, etc.)

1. Open **Ableton Live** > `Preferences` > `Link / MIDI`.
2. Under `MIDI Ports - Input`, find **`TouchStage Controller`**.
3. Enable **Track** and **Remote**.
4. Touch any fader or pad on the phone; the MIDI command is registered instantly.
