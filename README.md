# MacLocation

A small macOS menu bar app for switching a network interface between preset IP
configurations — handy when you need to talk to devices (switches, cameras,
routers, PLCs, access points…) that ship with a fixed default address, using
the same Ethernet adaptor you normally run on DHCP.

## Features

- Menu bar icon listing your presets, grouped by network service
  (e.g. `Ethernet`, `USB 10/100/1000 LAN`, `Thunderbolt Bridge`).
- Shows each service's current address, and ticks the preset that's active.
- One click applies a preset: static IP, subnet mask, optional router, optional DNS —
  or back to DHCP.
- Optionally shows the active preset's name next to the menu bar icon.
- Preset editor window: add, duplicate, reorder, validate, "Fill from Current
  Settings", and "Apply Now".
- Presets stored as plain JSON at
  `~/Library/Application Support/MacLocation/presets.json`.
- Launch at Login toggle.

## Requirements

- macOS 13 Ventura or later
- Swift 5.9+ (Xcode 15, or the Xcode Command Line Tools)

## Build & install

```sh
scripts/build-app.sh             # builds build/MacLocation.app
scripts/build-app.sh --install   # builds, copies to /Applications and launches it
```

For a quick run without bundling: `swift run`. (Launch at Login needs the `.app`.)

Each push also builds on GitHub Actions; the zipped `.app` is attached to the run
as the `MacLocation` artifact. Since it's only ad-hoc signed, the first time you open
a downloaded copy, right-click it and choose **Open** (or run
`xattr -dr com.apple.quarantine MacLocation.app`).

## Usage

1. Click the network icon in the menu bar → **Edit Presets…**
2. For each preset pick the **Network service** (the name shown in System
   Settings → Network), choose **Manually** or **Using DHCP**, and fill in the
   address. The subnet mask accepts `255.255.255.0` or a prefix length like `24`.
   Leave the router blank when talking directly to a device.
3. Pick a preset from the menu to apply it.

Changes are made with Apple's `/usr/sbin/networksetup`. If macOS requires
administrator rights for the change, you'll get the standard password prompt.

### Can't see the menu bar icon?

MacLocation has no Dock icon or main window; it lives only in the menu bar.
Double-click the app again to open the preset editor. If the icon is missing:

- On MacBooks with a notch, a crowded menu bar can hide icons behind the notch.
  MacLocation places its icon next to the clock on first launch. If it's hidden
  anyway, double-click the app and click the menu bar button at the bottom of
  the preset editor (**Move menu bar icon next to the clock**). You can also
  ⌘-drag the icon anywhere you like; macOS remembers where you put it.
- On macOS 26 or later, check **System Settings → Menu Bar** and make sure
  MacLocation is allowed in the menu bar.

### presets.json format

```json
[
  {
    "name": "Camera default",
    "service": "USB 10/100/1000 LAN",
    "mode": "manual",
    "ipAddress": "192.168.0.250",
    "subnetMask": "255.255.255.0",
    "router": "",
    "dnsServers": []
  },
  { "name": "Office DHCP", "service": "USB 10/100/1000 LAN", "mode": "dhcp" }
]
```

Missing keys fall back to sensible defaults, and `id` is generated if omitted.
Changes made to the file while the app is running are picked up after relaunch.

## What gets run

Applying a manual preset runs the equivalent of:

```sh
networksetup -setmanual "<service>" <ip> <mask> [<router>]
networksetup -setdnsservers "<service>" <dns…|Empty>
```

and a DHCP preset:

```sh
networksetup -setdhcp "<service>"
networksetup -setdnsservers "<service>" <dns…|Empty>
```
