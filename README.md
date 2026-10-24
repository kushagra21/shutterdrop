# Shutterdrop

**Wireless tethering for the Sony A7 III on macOS.** Shoot with the camera as
usual and every photo appears on your Mac about a second later. When you're
done, bring the full-size RAW and JPEG files across over Wi-Fi, already paired
with their previews.

No cables while shooting, no Sony software, and no Imaging Edge account.

> Shutterdrop currently supports the **Sony A7 III (ILCE-7M3)** only, tested
> with firmware 4.04. Other Sony bodies may work but haven't been tried.

## What it does

The A7 III has no Wi-Fi tethering to a computer, and Sony's Camera Remote SDK
doesn't support it. Shutterdrop combines two Wi-Fi modes the camera does have:

| While shooting | Afterwards |
|---|---|
| Camera on **Ctrl w/ Smartphone**. Each shot appears on the Mac **~1 s** after you press the shutter, as a 1616×1080 preview. | Camera on **Send to Computer**. Shutterdrop copies the full-size **ARW and/or JPEG** files over your home Wi-Fi and pairs each with its preview. |

## Features

- **Live previews** of every shot, taken with the camera's own shutter button.
- **Full-size import** over Wi-Fi:
  - Pick the photos to copy from a list with thumbnails.
  - Choose **RAW + JPEG**, **RAW only** or **JPEG only**.
  - See progress throughout; a cancelled or interrupted import carries on where it stopped.
- **Automatic matching** of each preview with its full-size files.
- **One-click camera pairing** over USB, needed once for Send to Computer.
- **Library you control:** choose where photos go. Shutterdrop keeps a `Shutterdrop` folder there, one folder per day.
- **Browse** by day with a large preview. Open files or show them in Finder.
- **Delete** photos, a selection or a whole day (to the Trash).
- **Fix wrong camera clocks:** shift a photo, a selection or a day to the right date.
- A **command-line tool** (`sdprobe`) for the same flow, plus camera probing.

## Requirements

- A Mac with **macOS 26** or later
- **Xcode 26** or later (Swift 6.2), to build it. Tested with Xcode 27.1.
- A **Sony A7 III** and a USB cable (used once, for pairing)
- A home **2.4 GHz Wi-Fi** network. The A7 III doesn't use 5 GHz.

## Quick start

```sh
git clone https://github.com/<you>/shutterdrop.git
cd shutterdrop
scripts/build-app.sh
open build/Shutterdrop.app
```

On first launch the app asks where to save photos, then shows a short setup
guide. Allow **Local Network** access when macOS asks.

Then:

1. **Pair once:** camera on USB in Mass Storage mode → **Camera → Pair Camera over USB…**
2. **Shoot:** camera on **Ctrl w/ Smartphone**, Mac on the camera's `DIRECT-…` Wi-Fi → **Start Live**
3. **Import:** Mac back on home Wi-Fi → **Import Full-Size**, camera on **Send to Computer**

📖 **[The user guide](docs/user-guide.md)** walks through every step with the
exact camera menus, plus troubleshooting.

## Good to know

- **Previews are 1616×1080.** That's what the camera sends over Wi-Fi while
  shooting. Full-size files come with the import.
- **While shooting, the Mac is on the camera's Wi-Fi**, so it has no internet
  unless it's also on Ethernet.
- **Import is slow-ish:** about 1 MB/s, roughly 20–30 s per 25 MB ARW. Choose
  the photos you need.
- **Set the camera's clock right.** Matching and day folders use the camera's
  time. Adjust Dates fixes photos taken with a wrong clock in Shutterdrop's
  library, but not inside the files (EXIF).

## Roadmap

- **Full-size tethering over USB:** RAW/JPEG straight to the Mac during the
  shoot, using the A7 III's PC Remote mode
- App icon
- Signed, notarized downloads, so you don't have to build it yourself
- Writing corrected dates into the files (EXIF), not just the library
- Open each new shot in Lightroom, Capture One or Preview automatically
- Launch at login, and auto-import whenever the camera starts Send to Computer
- Support for more Sony bodies (A7R III, A9, …) once tested

## How it works

Shutterdrop speaks the camera's own protocols directly:
- **Sony's Camera Remote API** for live previews
- **PTP/IP**, with Sony's extensions, for imports
- **A vendor USB command** for pairing

[docs/how-it-works.md](docs/how-it-works.md) covers the protocol details, what
was found testing the A7 III, the project layout and the developer tools.

## Acknowledgements

- [sony-pm-alt](https://github.com/falk0069/sony-pm-alt) by falk0069, and
  Clemens Fruhwirth's reverse-engineering of Sony's USB pairing command
- [libgphoto2](https://github.com/gphoto/libgphoto2), for documenting Sony's
  PTP/IP transfer handshake

Shutterdrop reimplements these protocols in Swift and contains no code from
either project.

## License

[MIT](LICENSE). Sony, Alpha and related names are trademarks of Sony Group
Corporation. Shutterdrop is an independent project, not affiliated with or
endorsed by Sony.
