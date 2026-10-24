# Shutterdrop

Wireless tethering for the Sony A7 III (ILCE-7M3) on macOS. When the camera and
the Mac are on the same Wi-Fi network, every photo you take shows up on the Mac
right away.

## Status

Step 1 (spike) built: `sdprobe` discovers devices over SSDP and speaks PTP/IP
(handshake, device info, session, events). It's tested against a fake camera,
but not yet against the real A7 III.

## Try it

```sh
swift build
swift test

# 1. Turn on the camera's Wi-Fi function, then look for it on the network.
.build/debug/sdprobe discover --seconds 15

# 2. Connect to the address marked ★ (or the camera's IP from its Wi-Fi info screen)
#    and take photos; every event is logged. Ctrl-C to stop.
.build/debug/sdprobe connect 192.168.0.x
.build/debug/sdprobe connect 192.168.0.x --sony-sdio   # if no events arrive
```

The first run asks for Local Network access for your terminal app. Allow it,
or nothing on the LAN is reachable.

## How it will work

- **Protocol:** PTP/IP (Picture Transfer Protocol over TCP/IP, port 15740). The
  A7 III speaks it when connected to a computer over Wi-Fi.
- **Discovery:** the camera announces itself on the local network via
  SSDP/UPnP. The Mac finds it, connects over PTP/IP, and listens for
  "new object" events from the camera.
- **Transfer:** on each new-photo event, download the file (JPEG and/or ARW)
  into a watch folder, and optionally open it in Preview, Lightroom, etc.

## Constraints found so far

- Sony's official Camera Remote SDK does **not** list the ILCE-7M3, so we
  implement PTP/IP ourselves (or via libgphoto2).
- Sony sends some non-standard PTP packets, so a plain PTP/IP client may need
  Sony-specific handling. Reference: https://github.com/falk0069/sony-pm-alt
- Which camera Wi-Fi mode allows *instant* per-shot transfer ("PC Remote" vs.
  "Send to Computer") still needs to be confirmed against a real camera.

## Plan

1. **Spike:** a command-line Swift tool that discovers the camera, completes the
   PTP/IP handshake, and logs events while you take photos.
2. **Transfer:** download each new photo to a folder as soon as it's taken.
   The core flow (discover → connect → event → download) lives in a library
   (`ShutterdropCore`), not the CLI, so the app can reuse it unchanged.
3. **App:** a regular SwiftUI Dock app on top of the core, so the tool is
   usable without the terminal:
   - Main window with a live grid of incoming shots and a large preview of
     the latest one, plus a toolbar showing connection state
     (searching / connected / receiving) with connect/disconnect.
   - Dock icon badge with the number of new shots in the session.
   - Settings: save folder, JPEG/ARW/both, file naming, open each shot in
     another app (Preview, Lightroom, Capture One), launch at login.
   - Auto-reconnect when the camera drops off Wi-Fi, and notifications.
   - First-run guide for setting up the camera's Wi-Fi mode and allowing
     Local Network access.

## Open camera checks

- Confirm the firmware shows **4.04** (Menu → Setup → Version).
- In the camera's **Network** menu, record whether **PC Remote Function**
  exists and its connection options (USB / Wi-Fi Direct / Wi-Fi Access Point),
  plus the other items (Send to Computer, Wi-Fi Settings, etc.).

## Requirements

- macOS 26+
- Xcode 27.1+ (macOS 27 SDK)
- Sony A7 III with recent firmware
