# Keys that arrive and are then ignored

| | |
|---|---|
| Problem | the hotkeys emit proper key events and nothing acts on them |
| Cause | `KEY_PROG1` has no assigned meaning, and no part of the stack switches the camera off |
| Fix | a small service that listens and acts, independently of the desktop |

```sh
sudo bash patch/hotkey-actions/install.sh
```

[`../hotkeys/`](../hotkeys/) is the other half: it makes the keys reach
userspace at all. This is what happens next.

## Why the desktop is not the place for this

**The performance key** arrives as `KEY_PROG1`, which literally means
"programmable key one". No desktop binds it, because there is nothing to bind
it to by default. A GNOME custom keybinding would work and would then not work
in KDE, or on the login screen, or with no session at all.

**The camera key** arrives as `KEY_CAMERA_ACCESS_TOGGLE`, and on this machine
nothing at all happens: measured here, the key press produces no USB event, the
EC does not cut power to the webcam, and no rfkill or privacy switch appears in
sysfs. On Windows the vendor's PC Manager does it in software. So something has
to.

## What it does

| Key | Action |
|---|---|
| `KEY_PROG1` | cycles power-saver → balanced → performance through `power-profiles-daemon` |
| `KEY_CAMERA_ACCESS_TOGGLE` | deauthorises the webcam on the USB bus, and back |
| `KEY_CAMERA_ACCESS_ENABLE` / `_DISABLE` | the same, one direction each |

Cycling rather than jumping to a fixed profile, because there is one key and
that is what it does on Windows.

Deauthorising is what a privacy switch does in software: writing `0` to the USB
device's `authorized` unbinds the driver and the camera leaves `/dev/video*`
entirely. Verified here, `/dev/video0` and `/dev/video1` disappear and come
back. Anything holding the camera open loses it, which is the point.

It is not a hardware cut. Somebody with root can authorise it again, exactly as
this service does. If you want certainty, use the physical shutter.

## Configuration

`/etc/honor-hotkey-actions.conf`, written by the installer:

```
POWER_PROFILE_KEY=1
CAMERA_KEY=1
CAMERA_USB="3277:00de"
```

Set either to `0` and restart the service, or pass it to the installer:

```sh
sudo CAMERA_KEY=0 bash patch/hotkey-actions/install.sh
```

The camera's USB id comes from the device profile's `camera_usb`, so a model
with a different webcam needs that field rather than an edit here.

## Watching it

```sh
journalctl -u honor-hotkey-actions -f
```

Each action logs one line. If a key press produces nothing there, the key is
not reaching the service, which is a [`../hotkeys/`](../hotkeys/) problem
rather than this one; `capture-keys.sh` in that directory tells the two apart.

## What it deliberately does not do

It never injects input events, only reads them. It writes exactly two things:
a power profile through `powerprofilesctl`, and `authorized` on one USB device.
The systemd unit is confined accordingly, with `ProtectSystem=strict` and
`/sys/bus/usb/devices` as the only writable path.

The keyboard backlight keys are not handled by this service. On the ZQC-P the
firmware exposes three EC-backed levels, but the in-tree WMI path may return
`-ENODEV`; use the dedicated keyboard-backlight fix when it is enabled for the
profile. If `/sys/class/leds/huawei::kbd_backlight` exists but writes fail,
include that output in `tools/doctor.sh --json` and open an issue.
to drive: the EC appears to handle the backlight itself and only notify the OS
afterwards, which is what the `0x2e5` code is. Nothing to act on.
