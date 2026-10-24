# How Shutterdrop works

Notes for developers: what the A7 III does over Wi-Fi and USB, how Shutterdrop
uses it, and how the code is laid out. Everything here was measured on an A7 III
running firmware 4.04, with macOS 26.

## Why two Wi-Fi modes

The A7 III offers no Wi-Fi tethering to a computer:

- **PC Remote is USB-only.** The Network menu has the smartphone functions and
  Send to Computer, nothing else.
- **Sony's Camera Remote SDK doesn't support the ILCE-7M3** (it starts at the
  A7 IV).

Shutterdrop therefore combines two modes the camera does have:

| | Ctrl w/ Smartphone | Send to Computer |
|---|---|---|
| Network | Camera is a Wi-Fi Direct access point, at `192.168.122.1` | Camera joins your Wi-Fi |
| Protocol | Sony Camera Remote API (JSON-RPC over HTTP) | PTP/IP (port 15740) with Sony extensions |
| New-shot notification | Yes, ~1 s after each press of the shutter button | No; batch only |
| Image you get | 1616×1080 postview JPEG | Full-size ARW / JPEG |
| Needs pairing | No | Yes, once over USB |

Previews and originals are paired afterwards by camera time.

## Live previews: Camera Remote API

In Ctrl w/ Smartphone mode the camera:
- announces itself over SSDP as `urn:schemas-sony-com:service:ScalarWebAPI:1`,
  `SERVER: UPnP/1.0 SonyImagingDevice/1.0`;
- serves a device description at `http://192.168.122.1:64321/dd.xml`;
- runs the API at `http://192.168.122.1:10000/sony` ("Smart Remote Control"
  2.1.7, `camera` API versions 1.0–1.8).

`camera.getEvent [true]` long-polls. Its result is a positional array whose
slots are `null`, objects or arrays of objects, each tagged with `"type"`.
Shutterdrop reads two kinds:
- `cameraStatus`, which goes `IDLE` → `StillCapturing` → `IDLE` around each shot;
- `takePicture`, whose `takePictureUrl` is the shot's postview, e.g.
  `http://192.168.122.1:60152/pict261024_1338460000.JPG?…`.

A press of the camera's own shutter button produces a `takePicture` event about
1 s later. `actTakePicture` also works, but Shutterdrop doesn't need it.

Postviews are **1616×1080**. The A7 III doesn't offer `setPostviewImageSize`;
the call returns error 40401. Their names carry the camera's local time,
`pict<yyMMdd>_<HHmmss>` plus four digits, and the camera names them **1–2 s
after** the shutter press. The PTP/IP port is closed in this mode.

Code: `RemoteCamera`, `LiveSession`.

## Full-size import: PTP/IP

After pairing, choosing **Send to Computer** makes the camera:
1. join the configured Wi-Fi;
2. announce itself over SSDP as `urn:microsoft-com:service:MtpNullService:1`
   (`SERVER: FedoraCore/2 UPnP/1.0 MINT-X/1.9.1`);
3. open PTP/IP on port 15740, usually a second or so after the announcement.
   The importer retries the connection for 20 s.

The importer then:
1. Opens the PTP/IP command and event channels, with the paired GUID in
   `Init_Command_Request`.
2. Runs `GetDeviceInfo` and `OpenSession`. The A7 III reports vendor extension
   `0xFFFFFFFF`, firmware "4.0" and operations including `0x9280`–`0x9285` and
   the MTP property operations `0x9801`–`0x9805`.
3. Sends **Sony's transfer handshake**, as libgphoto2 does:
   - Operation `0x9280(4)` with an 18-byte data phase: UInt32s `2, 2, 0, 0`,
     then bytes `1, 1`.
   - Operation `0x9281(4)`, whose returned data is ignored.

   With this the camera shows **"Sending… <computer name>"** and keeps the
   session open (tested for 11 minutes). **Without it the camera drops the
   connection after about 2 minutes.**
4. Lists every object (`GetStorageIDs`, `GetObjectHandles`, `GetObjectInfo`) and
   keeps JPEG (`0x3801`) and Sony ARW (`0xB101`) files in the requested date
   range. This takes about 20 s, because the camera answers one object at a time.
5. Offers the new ones for choosing, with thumbnails from `GetThumb`.
6. Copies the chosen files (`GetObject`), then sends the finish handshake:
   `0x9280(4)` with UInt32s `0, 5, 0, 0`, then `0x9281(4)`. The camera saves and
   powers off.

The event channel only ever carries StoreAdded, StoreRemoved and
DevicePropChanged in this mode. Taking a photo produces nothing, so this mode
can't do live tethering.

**Speed:** about 1.2 MB/s at first, falling to about 0.2 MB/s over an
11-minute import of 25 MB ARWs. Imports skip files already in the library,
matched by name and size anywhere in it, so an interrupted import resumes.

Code: `PTPIPClient` (transactions are queued, so thumbnails can load in
parallel), `CardImporter`.

## Pairing: Sony's USB command

Send to Computer only talks to a computer whose GUID the camera has stored.
The camera stores it from a vendor SCSI command over **USB Mass Storage**
(Bulk-Only Transport). Clemens Fruhwirth reverse-engineered it; see
sony-pm-alt's `sony-guid-setter`.

- **Command:** CDB `7A 04 00 00 00 00 00 00 00` (9 bytes), addressed to the LUN
  returned by Get Max LUN. That's 2 on the A7 III.
- **Data out, 8192 bytes:**
  - offset 0: `25 01 00 00 08`
  - offset 17: the computer name, 16 bytes of UTF-16LE (8 characters)
  - offset 177: `10 00 00 00`
  - offset 181: the 16-byte GUID
  - every other byte is zero.
- **Status:** a standard 13-byte CSW. Status 0 means accepted.

Shutterdrop sends this with **IOUSBHost**. The process:
1. **Captures** the camera's USB device, which needs root. This detaches
   macOS's storage driver, so the card disappears.
2. Configures the device and opens the mass storage interface.
3. Sends the command and data, then reads the status.
4. Destroys the device object, so macOS resets the camera and takes it back.

macOS details that each cost a debugging round:
- `IOUSBHostDevice.createMatchingDictionary(withVendorID:…)` produces a
  top-level `idVendor` key that matches nothing from user space. Use
  `IOPropertyMatch` instead.
- `ioData(withCapacity:)` buffers have a fixed length, and setting `length`
  throws an Objective-C exception. Use plain `NSMutableData`.
- AppleScript's `do shell script … with administrator privileges` runs the
  command **outside the user's login session**. Capturing the device works
  there, but opening its interface fails with `kIOReturnInternalError`
  (`0xE00002C9`). The app therefore runs the bundled `sdprobe pair` via
  `launchctl asuser <uid>`.

The GUID lives in `~/Library/Application Support/Shutterdrop/client-guid`.
Deleting it means pairing again.

Code: `CameraPairing`, `ClientIdentity`.

## Matching and the library

```
<chosen location>/Shutterdrop/<yyyy-MM-dd>/previews/pict….JPG
                                          /originals/DSC0….ARW|JPG
```

- **Days follow the camera's clock.** Only `yyyy-MM-dd` and `undated` folders
  count as days, so a library inside e.g. `~/Downloads` never touches other
  folders.
- **An original's capture time** is kept as its file modification date.
- **Matching** (`ShotMatcher`) groups originals by base name, so
  `DSC04662.JPG` + `DSC04662.ARW` is one shot. Each preview takes the closest
  unclaimed shot taken up to 4 s before it or 1 s after it.
- **Adjust Dates** (`PhotoLibrary.shiftDates`) moves files to the corrected day,
  renames previews to the corrected time and resets originals' file dates. EXIF
  inside the files is not changed.
- **Deleting** moves files to the Trash.

Code: `PhotoLibrary`, `ShotMatcher`.

## Project layout

```
Sources/
  PTPIP/            PTP/IP packets, datasets and an async client (Network framework)
  SSDP/             SSDP search and announcements (BSD sockets)
  ShutterdropCore/  Live previews, import, pairing, library, matching
  Shutterdrop/      The SwiftUI Dock app
  sdprobe/          Command-line tool
Tests/              Swift Testing suites (no camera needed)
scripts/
  build-app.sh            Build build/Shutterdrop.app (bundles sdprobe for pairing)
  probe-wifi-direct.sh    Offline probe for Ctrl w/ Smartphone mode
  probe-remote-api.sh     Offline Camera Remote API probe
```

## Developing

```sh
swift build            # everything
swift test             # unit tests; no camera needed
scripts/build-app.sh   # the app bundle
```

- **Probe scripts:** the scripts in `scripts/` run while the Mac is on the
  camera's Wi-Fi, where it has no internet. They write their logs to
  `~/Desktop`.
- **Window snapshot:** `SHUTTERDROP_SNAPSHOT=/tmp/shot.png
  build/Shutterdrop.app/Contents/MacOS/Shutterdrop` saves a PNG of the window
  after launch. It doesn't need Screen Recording permission, but it can't
  render the macOS 26 glass sidebar and toolbar.
- **The app bundle:** ad-hoc signed, with `NSLocalNetworkUsageDescription` so
  macOS asks for Local Network access.
