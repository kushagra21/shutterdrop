# Shutterdrop user guide

This guide takes you from nothing to wireless tethering with a Sony A7 III. It
takes about 15 minutes the first time. After that, each shoot is two clicks.

**Contents**
1. [What you need](#1-what-you-need)
2. [Build and open the app](#2-build-and-open-the-app)
3. [Choose where photos go](#3-choose-where-photos-go)
4. [Prepare the camera](#4-prepare-the-camera)
5. [Pair the camera (once)](#5-pair-the-camera-once)
6. [Shoot with live previews](#6-shoot-with-live-previews)
7. [Import the full-size files](#7-import-the-full-size-files)
8. [Browse, delete and fix dates](#8-browse-delete-and-fix-dates)
9. [Troubleshooting](#9-troubleshooting)
10. [Command line (optional)](#10-command-line-optional)

Camera menu paths are written like **MENU → Network → Send to Computer**:
press MENU, open the Network tab (the globe icon), then choose Send to
Computer.

---

## 1. What you need

- A Mac with **macOS 26** or later
- **Xcode** 26 or later, free from the Mac App Store. Open it once after
  installing so it can finish setting up.
- A **Sony A7 III**. Tested with firmware 4.04; check yours under
  **MENU → Setup → Version**.
- A **USB cable** for the camera, used once
- Your home **Wi-Fi**. The A7 III only uses 2.4 GHz networks.

## 2. Build and open the app

Open **Terminal** (Applications → Utilities) and run:

```sh
git clone https://github.com/kushagra21/shutterdrop.git
cd shutterdrop
scripts/build-app.sh
open build/Shutterdrop.app
```

The build takes a minute or two. The app is built on your Mac, so macOS opens
it without complaint. To keep it handy, drag `build/Shutterdrop.app` into your
Applications folder.

The first time Shutterdrop looks for the camera, macOS asks to let it find
devices on your **local network**. Click **Allow**, or it can't see the camera.
To change this later, go to System Settings → Privacy & Security → Local
Network.

## 3. Choose where photos go

On first launch, Shutterdrop asks **"Where should Shutterdrop save photos?"**
- **Use This Folder** keeps the suggested `Pictures`.
- **Choose Another…** picks any other location, for example an external drive.

Shutterdrop creates a folder called **`Shutterdrop`** there and keeps one
folder per day inside it:

```
Shutterdrop/
  2026-10-24/
    previews/    ← live previews (1616×1080 JPEG)
    originals/   ← full-size ARW / JPEG files
```

The bottom of the sidebar always shows where photos are going. To change it
later, use the **⋯** button there, **File → Change Photo Folder…** or Settings.
Shutterdrop offers to move your existing photos across.

## 4. Prepare the camera

Do this once.

1. **Set the clock:** **MENU → Setup → Date/Time Setup.** Shutterdrop pairs
   previews with full-size files and files them by day using the camera's
   clock, so it should be right. If it was wrong for some photos, see
   [Fix wrong dates](#fix-wrong-dates).
2. **Join your home Wi-Fi:** **MENU → Network → Wi-Fi Settings → Access Point
   Set.** Choose your network and enter its password. Pick the 2.4 GHz network
   if your router shows two names.
3. **Make sure Airplane Mode is off:** **MENU → Network → Airplane Mode.**

## 5. Pair the camera (once)

The camera only sends files to a computer it has been introduced to over USB.
Without this step, Send to Computer says *"the information of the computer is
not set"*.

> **Use at your own risk.** Pairing sends a vendor command that Sony doesn't
> document for this use. It registers your Mac on the camera, just as Sony's
> own software does. It worked reliably in testing, but Shutterdrop comes with
> no warranty. Use a charged battery and don't unplug the camera while pairing.

1. On the camera: **MENU → Setup → USB Connection → Mass Storage**.
2. Connect the camera to the Mac with the USB cable and turn it on.
3. If the camera's memory card appears in Finder, **eject it**. Leave the cable
   plugged in.
4. In Shutterdrop choose **Camera → Pair Camera over USB…** and click **Pair**.
5. Enter your Mac password when macOS asks.
6. You should see **"Camera paired"**. Unplug the camera and set **USB
   Connection** back to what it was (usually **Auto**).

You only need to do this again if you reset the camera's network settings, or
pair it with other software.

## 6. Shoot with live previews

1. On the camera: **MENU → Network → Ctrl w/ Smartphone**. Turn it on if
   needed, then choose **Connection**. The camera shows a Wi-Fi network name
   like `DIRECT-xxxx:ILCE-7M3` and a password.
2. On the Mac, join that network from the Wi-Fi menu in the menu bar and enter
   the password.
3. In Shutterdrop click **Start Live** (or press **⌘L**). The toolbar dot turns
   green: *Live: ready*.
4. Shoot as normal with the camera's shutter button. Each photo appears in the
   app about a second later and is selected automatically. An orange
   **Preview** badge means the full-size file hasn't been imported yet.

When you're done, click **Stop Live**. If Shutterdrop is in the background, the
Dock icon counts the new shots.

While the Mac is on the camera's Wi-Fi it has **no internet**, unless it's
also connected by Ethernet.

## 7. Import the full-size files

1. Switch the Mac back to your **home Wi-Fi**.
2. In Shutterdrop click **Import Full-Size** (or press **⇧⌘I**).
3. Choose which photos to look at: **Today**, **Last 7 days** or
   **Everything on the card**. Click **Start**.
4. On the camera: **MENU → Network → Send to Computer**. It should show
   **"Sending… Shutterdrop"**.
5. The sheet ticks off the steps as it goes: *camera found*, *connected*,
   *reading the card (n of N)*. Reading the card takes around 20 seconds.
6. **Choose what to copy.** Every new photo in your range is listed with a
   thumbnail and starts ticked.
   - **Select All**, **Select None**, or click photos to tick and untick them.
   - **RAW + JPEG / RAW only / JPEG only** sets which files are downloaded for
     the ticked photos. Your choice is remembered.
7. Click **Import N Files**. Expect about 20–30 seconds per RAW file. When it's
   done, the camera saves and switches itself off.

Files already in your library are never copied twice. **Cancel** closes the
sheet at once. The file being copied finishes in the background, and the next
import carries on from there.

## 8. Browse, delete and fix dates

**Browse:** pick a day in the sidebar and click a photo to see it large. The
panel below shows its preview and full-size files, with buttons to **open**
them or **show them in Finder**.

**Select several photos:** ⌘-click to add or remove a photo, ⇧-click to select
a range, or press ⌥⌘A to select all.

**Delete:** everything goes to the Trash, so you can put it back from Finder.
A photo's preview and its full-size files are deleted together.
- **Photos:** select them, then use **Move to Trash…** (below the large
  preview), right-click → **Move to Trash…**, or press **⌘⌫**.
- **A whole day:** right-click it in the sidebar → **Move Day to Trash…**

### Fix wrong dates

If the camera's clock was wrong, its photos end up on the wrong day.

1. Right-click the day (or a photo) → **Adjust Dates…**, or press **⇧⌘D**.
2. Under **Actually taken**, enter when the shown photo was really taken.
   Shutterdrop works out the shift, for example "−30 days 0 h 9 min".
3. Apply it to **this photo**, the **selected photos** or **all photos on that
   day**.

The photos move to the right day and stay paired. This changes Shutterdrop's
folder only; the date stored inside the files (EXIF) stays as the camera wrote
it. Lightroom and Photos can change that too.

## 9. Troubleshooting

| Problem | What to do |
|---|---|
| **Live stays on "Looking for camera…"** | Make sure the Mac is on the camera's `DIRECT-…` network and Ctrl w/ Smartphone is still showing on the camera. Check Local Network access is allowed (System Settings → Privacy & Security → Local Network). |
| **Import waits for the camera forever** | The Mac must be on the **same home Wi-Fi** as the camera; the sheet says which network the Mac is on. On the camera, start **Send to Computer** again. Check the camera joined your Wi-Fi (section 4, step 2). |
| **Camera says "the information of the computer is not set"** | Pair it (section 5). |
| **Camera shows "Sending" but import fails or stops** | Keep the camera close to the router with a charged battery. Start the import again; already-copied files are skipped. |
| **Pairing says no camera / not Mass Storage** | Set **USB Connection → Mass Storage**, reconnect the cable, eject the card in Finder, and try again. |
| **Photos are on the wrong day** | The camera's clock was wrong. Use **Adjust Dates** (section 8) and fix the camera clock. |
| **Previews don't match their full-size files** | Matching uses the camera's time. Make sure both came from the same camera clock. If you adjusted dates, adjust the whole day, not just previews. |
| **Import is slow** | It's the camera's Wi-Fi, about 1 MB/s. Choose **JPEG only** or fewer photos. |

## 10. Command line (optional)

`sdprobe` does the same from Terminal, for scripting or debugging. Build it
with `swift build`, then:

```sh
.build/debug/sdprobe live                                 # save previews; Ctrl-C to stop
.build/debug/sdprobe import --since 2026-10-24 --dry-run  # list what's new
.build/debug/sdprobe import --since 2026-10-24            # copy it
sudo .build/debug/sdprobe pair                            # pair over USB
.build/debug/sdprobe discover --seconds 15                # list devices on the network
.build/debug/sdprobe --help
```

It uses the same camera pairing and folder layout as the app, but saves to
`~/Pictures/Shutterdrop` unless you pass `--out <folder>`, rather than the
folder chosen in the app.
