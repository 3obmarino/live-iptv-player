# LiveTV Player

A small, clean IPTV player: **Live TV + TV guide (EPG) only**, for
Windows, Android phones and Google TV.
Flutter UI, libmpv playback (via media_kit), Xtream Codes and M3U playlists.

## Install

| Device | How |
|---|---|
| **Google TV / Android TV** | In the **Downloader** app enter code **`8371457`** |
| Windows | `LiveTV-Player-Windows-Setup-<version>.exe` (or the portable `.zip`) from [latest release](https://github.com/3obmarino/live-iptv-player/releases/latest) |
| Android phone | `LiveTV-Player-Phone-<version>.apk` from [latest release](https://github.com/3obmarino/live-iptv-player/releases/latest) |

The Downloader code always points to the newest TV version:
`https://github.com/3obmarino/live-iptv-player/releases/latest/download/LiveTV-TV.apk`.
After the first install, every app updates itself (Menu/Settings › Check for updates).

## What it does
- Profiles: Xtream Codes (server / username / password) or M3U URL
- Channel grid with logo, current programme and progress bar
- Full-page category picker with favourite categories, plus favourite channels
- Timeline TV guide (EPG) with a "now" line; right-click a programme for details
- **EPG auto refresh that works**: a scheduler checks every minute whether the
  guide is older than the chosen frequency (1h … 7 days) and refreshes it.
  It also catches up after the PC has been asleep. Default: every day.
- EPG time shift and custom XMLTV URL (.xml or .xml.gz)
- Player: auto-reconnect, channel up/down, channel list, fullscreen, info overlay
- Light / dark / follow Windows theme

Player keys: ↑/↓ or PgUp/PgDn channel · ←/→ volume · Space pause · F fullscreen ·
M mute · L channel list · I info · Esc back.

## Getting the installer (no tools needed on your PC)
1. Create a **private** GitHub repository and upload this folder's contents
   (including the hidden `.github` folder).
2. GitHub → *Actions* → "Build and release" runs automatically
   (or press *Run workflow*). Takes ~10 minutes.
3. Open the finished run → *Artifacts* → download `LiveTV-Player-Windows`.
   It contains the setup `.exe` and the portable `.zip`.

Pushing a tag like `v1.0.0` also attaches the files to a GitHub Release.

## Building locally (optional)
Requires Flutter 3.24+ and Visual Studio 2022 with "Desktop development with C++".
```
flutter create --platforms=windows --project-name live_tv_player .
flutter pub get
flutter run -d windows        # or: flutter build windows --release
```

## Privacy & security
- Your IPTV login (username, password, playlist and EPG URLs) is stored only on
  your own device, encrypted by the operating system (Windows DPAPI, Android
  Keystore). It is never in this repository and never sent anywhere except to
  your provider. Android cloud backup is disabled.
- Updates are only installed after their SHA-256 matches the checksum GitHub
  publishes for the release.
- The Android signing key is a repository secret (`ANDROID_KEYSTORE_B64`,
  base64 of the keystore), not a file in the repo.
- GitHub Actions are pinned to commit SHAs; the workflow token is read-only
  except for the release step.

## Data
Settings, profile names, channel lists and the cached guide are stored in
`%APPDATA%\dk.livetvplayer\live_tv_player\` (JSON files).
