# Shutterdrop

Wireless tethering for the Sony A7 III (ILCE-7M3) on macOS. When the camera and
the Mac are on the same Wi-Fi network, every photo you take shows up on the Mac
right away.

## Status

Step 3 (Dock app) in progress. The core flow (step 2) works on the real A7 III:
5 live previews saved ~1–2 s after each shot, then 15 ARWs imported and all 5
previews matched to their originals.

## Try it

```sh
swift test
scripts/build-app.sh && open build/Shutterdrop.app   # the Dock app
```

In the app: **Start Live** while shooting (camera on Ctrl w/ Smartphone, Mac on
the camera's `DIRECT-…` Wi-Fi), then **Import Full-Size** afterwards (Mac back on
home Wi-Fi, camera on Send to Computer). On first run the app asks where to
save photos (default `~/Pictures/Shutterdrop`); the sidebar footer shows the
folder and can change it, moving existing photos if you like. Inside, photos go
to `<date>/previews` and `<date>/originals`, dated by the camera's clock.
Pair the camera from Camera → Pair Camera over USB. Allow Local Network access
when macOS asks.

The same flow from the command line:

```sh
.build/debug/sdprobe live                         # Ctrl-C to stop
.build/debug/sdprobe import --since 2026-10-24 --dry-run
.build/debug/sdprobe import --since 2026-10-24
.build/debug/sdprobe discover --seconds 15        # probing
```

## Pairing (one time, USB)

Send to Computer refuses to start ("computer information not set") until a
computer is registered on the camera over USB.

1. Camera: MENU → Setup → USB Connection → **Mass Storage**; plug it in and
   eject its disks in Finder, keeping the cable connected.
2. In the app: **Camera → Pair Camera over USB…** (asks for an administrator
   password), or from Terminal: `sudo .build/debug/sdprobe pair`.
3. Unplug and set USB Connection back.

Pairing registers the ID in `~/Library/Application Support/Shutterdrop/client-guid`;
don't delete that file, or the camera has to be paired again. The protocol (a
vendor SCSI command 0x7A plus an 8 KB block with the name and ID) was
reverse-engineered by Clemens Fruhwirth for sony-pm-alt's `sony-guid-setter`;
Shutterdrop reimplements it with IOUSBHost. It needs root, and when launched
through AppleScript's administrator prompt it must run via
`launchctl asuser <uid>`, or opening the USB interface fails.

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
- **Pairing:** "Send to Computer" refuses to start until a computer is
  registered over USB. sony-pm-alt's `sony-guid-setter` (camera in USB Mass
  Storage mode, run with sudo) registered Shutterdrop's GUID on macOS 26.
  The app will need its own Swift version of this step.
- **Send to Computer is batch-only (tested 2026-10-24):** after pairing, the
  camera announces itself over SSDP (`FedoraCore/2 UPnP/1.0 MINT-X`,
  `MtpNullService`), accepts PTP/IP on 15740 and exposes its card, but only
  advertises StoreAdded/StoreRemoved/DevicePropChanged events. Taking a photo
  produced no event. It suits "import new photos", not instant transfer.
- **No PC Remote over Wi-Fi** on the A7 III. The Network menu only has the
  smartphone functions and Send to Computer.
- **Ctrl w/ Smartphone = instant previews (tested 2026-10-24):** the camera
  becomes a Wi-Fi Direct access point (camera at 192.168.122.1) and runs Sony's
  Camera Remote API (ScalarWebAPI, "Smart Remote Control" 2.1.7, JSON-RPC at
  `http://192.168.122.1:10000/sony`, description at `:64321/dd.xml`). Long-polling
  `camera.getEvent [true]` reports a `takePictureUrl` **~1 s after each press of
  the camera's own shutter button**. `actTakePicture` also works. The image at
  that URL is a **1616×1080 JPEG** (~360 KB), not the full file;
  `setPostviewImageSize` is not offered. The PTP/IP port is closed in this mode.
  Downside: the Mac has to join the camera's Wi-Fi, so it loses the home network
  unless it has a second connection (Ethernet).

## Plan

1. **Spike:** a command-line Swift tool that discovers the camera, completes the
   PTP/IP handshake, and logs events while you take photos.
2. **Transfer (combined approach):** live previews over Wi-Fi Direct while
   shooting, full-size import over Send to Computer afterwards, paired by
   camera time. The core flow lives in a library (`ShutterdropCore`), not the
   CLI, so the app can reuse it unchanged. Full-size tethering over USB may
   come later as a third mode.
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

- Firmware 4.04 confirmed (EXIF `ILCE-7M3 v4.04`; PTP reports "4.0").
- The camera's clock was ~30 days fast until 2026-10-24; shots from before the
  fix are dated up to 2026-11-23 and land in that library folder.
- **Send to Computer needs Sony's 0x9280/0x9281 handshake** (as libgphoto2 does
  it): with it the camera shows "Sending… Shutterdrop", stays connected
  (11 min tested) and shuts down when done; without it the camera drops the
  connection after ~2 minutes.
- **Import is slow over Wi-Fi:** listing the card takes ~17–20 s, and speed
  fell from ~1.2 MB/s to ~0.2 MB/s over an 11-minute import (25 MB ARWs). The
  app needs progress and resume (re-running already skips copied files).
- The camera announces itself over SSDP a second or so before port 15740
  accepts connections; the importer retries for 20 s.

## Requirements

- macOS 26+
- Xcode 27.1+ (macOS 27 SDK)
- Sony A7 III with recent firmware
