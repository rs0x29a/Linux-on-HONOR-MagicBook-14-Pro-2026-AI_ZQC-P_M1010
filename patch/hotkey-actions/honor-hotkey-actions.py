#!/usr/bin/env python3
"""Give the HONOR hotkeys something to do.

patch/hotkeys/ makes the keys arrive as proper key events. That is where the
kernel's job ends: KEY_PROG1 means "programmable key one" and no desktop binds
it, and nothing in the stack turns KEY_CAMERA_ACCESS_TOGGLE into a camera that
is actually off. On Windows the vendor's PC Manager does both.

This listens on the WMI hotkey device and acts, so it works the same under
GNOME, KDE or no desktop at all. Read-only on the input device; it never
injects events.

Configured by /etc/honor-hotkey-actions.conf, written by install.sh.
"""

import errno
import os
import pwd
import re
import select
import struct
import subprocess
import sys
import time

EVENT_FMT = "llHHi"                      # struct input_event
EVENT_SIZE = struct.calcsize(EVENT_FMT)
EV_KEY = 0x01

KEY_PROG1 = 148
KEY_CAMERA_ACCESS_TOGGLE = 589
KEY_CAMERA_ACCESS_ENABLE = 590
KEY_CAMERA_ACCESS_DISABLE = 591

CONF = "/etc/honor-hotkey-actions.conf"
DEVICE_NAME = "Huawei WMI hotkeys"


def log(msg):
    print(msg, flush=True)


def read_conf():
    cfg = {}
    try:
        with open(CONF) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"')
    except FileNotFoundError:
        pass
    return cfg


def find_device():
    """The event number moves when huawei-wmi is reloaded, so match on name."""
    for entry in sorted(os.listdir("/sys/class/input")):
        if not entry.startswith("event"):
            continue
        try:
            with open(f"/sys/class/input/{entry}/device/name") as f:
                if f.read().strip() == DEVICE_NAME:
                    return f"/dev/input/{entry}"
        except OSError:
            continue
    return None


# --- actions -----------------------------------------------------------------

PROFILE_ORDER = ["power-saver", "balanced", "performance"]


def cycle_power_profile():
    """Step to the next profile power-profiles-daemon offers.

    Cycling rather than jumping to a fixed one, because that is what the key
    does on Windows and there is only one key.
    """
    try:
        have = subprocess.run(["powerprofilesctl", "list"], capture_output=True,
                              text=True, timeout=5).stdout
        available = [p for p in PROFILE_ORDER if re.search(rf"^\s*\*?\s*{p}:", have, re.M)]
        if not available:
            log("power profiles: none offered by power-profiles-daemon")
            return
        cur = subprocess.run(["powerprofilesctl", "get"], capture_output=True,
                             text=True, timeout=5).stdout.strip()
        nxt = available[(available.index(cur) + 1) % len(available)] if cur in available else available[0]
        subprocess.run(["powerprofilesctl", "set", nxt], timeout=5, check=True)
        log(f"power profile: {cur} -> {nxt}")
    except FileNotFoundError:
        log("power profiles: powerprofilesctl not installed")
    except Exception as e:                                    # noqa: BLE001
        log(f"power profiles: {e}")


def camera_sysfs_paths(usb_id):
    """USB devices matching vid:pid, as sysfs directories."""
    vid, pid = usb_id.lower().split(":")
    out = []
    base = "/sys/bus/usb/devices"
    for d in os.listdir(base):
        p = os.path.join(base, d)
        try:
            with open(os.path.join(p, "idVendor")) as f:
                if f.read().strip().lower() != vid:
                    continue
            with open(os.path.join(p, "idProduct")) as f:
                if f.read().strip().lower() != pid:
                    continue
        except OSError:
            continue
        out.append(p)
    return out


def set_camera(usb_id, on):
    """Authorise or deauthorise the camera on the USB bus.

    Deauthorising is what a privacy switch does in software: the device stays
    physically attached but the kernel unbinds it and it disappears from
    /dev/video*. Nothing that has the camera open keeps it.
    """
    paths = camera_sysfs_paths(usb_id)
    if not paths:
        log(f"camera: no USB device {usb_id} present")
        return None
    state = "1" if on else "0"
    for p in paths:
        try:
            with open(os.path.join(p, "authorized"), "w") as f:
                f.write(state)
        except OSError as e:
            log(f"camera: cannot write authorized on {p}: {e}")
            return None
    log(f"camera: {'on' if on else 'off'}")
    return on


def camera_is_on(usb_id):
    for p in camera_sysfs_paths(usb_id):
        try:
            with open(os.path.join(p, "authorized")) as f:
                return f.read().strip() == "1"
        except OSError:
            pass
    return None


def show_camera_osd(on):
    try:
        session = subprocess.run(
            ["loginctl", "show-seat", "seat0", "-p", "ActiveSession", "--value"],
            capture_output=True, text=True, timeout=3).stdout.strip()
        if not session:
            return
        uid = int(subprocess.run(
            ["loginctl", "show-session", session, "-p", "User", "--value"],
            capture_output=True, text=True, timeout=3).stdout.strip())
        if uid <= 0 or not os.path.exists(f"/run/user/{uid}/bus"):
            return
        user = pwd.getpwuid(uid).pw_name
        result = subprocess.run([
            "runuser", "-u", user, "--", "env",
            f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus",
            "qdbus6", "org.kde.plasmashell", "/org/kde/osdService",
            "org.kde.osdService.showText", "camera-on" if on else "camera-off",
            "Camera Enabled" if on else "Camera Disabled",
        ], capture_output=True, text=True, timeout=3)
        if result.returncode:
            log(f"camera OSD failed: {result.stderr.strip() or result.returncode}")
    except (FileNotFoundError, KeyError, OSError, ValueError, subprocess.SubprocessError) as e:
        log(f"camera OSD failed: {e}")


def set_camera_with_osd(usb_id, on):
    state = set_camera(usb_id, on)
    if state is not None:
        show_camera_osd(state)
    return state


# --- main loop ---------------------------------------------------------------

def main():
    cfg = read_conf()
    do_profile = cfg.get("POWER_PROFILE_KEY", "1") == "1"
    camera_id = cfg.get("CAMERA_USB", "")
    do_camera = bool(camera_id) and cfg.get("CAMERA_KEY", "1") == "1"

    log(f"power profile key: {'on' if do_profile else 'off'}")
    log(f"camera key: {('on, ' + camera_id) if do_camera else 'off'}")

    while True:
        dev = find_device()
        if not dev:
            log(f"waiting for '{DEVICE_NAME}'")
            time.sleep(5)
            continue
        try:
            fd = os.open(dev, os.O_RDONLY)
        except OSError as e:
            log(f"cannot open {dev}: {e}")
            time.sleep(5)
            continue
        log(f"listening on {dev}")
        try:
            while True:
                r, _, _ = select.select([fd], [], [], 60)
                if not r:
                    continue
                data = os.read(fd, EVENT_SIZE * 16)
                for off in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
                    _, _, etype, code, value = struct.unpack_from(EVENT_FMT, data, off)
                    if etype != EV_KEY or value != 1:      # key press only
                        continue
                    if code == KEY_PROG1 and do_profile:
                        cycle_power_profile()
                    elif do_camera and code == KEY_CAMERA_ACCESS_TOGGLE:
                        cur = camera_is_on(camera_id)
                        set_camera_with_osd(camera_id, not cur if cur is not None else False)
                    elif do_camera and code == KEY_CAMERA_ACCESS_ENABLE:
                        set_camera_with_osd(camera_id, True)
                    elif do_camera and code == KEY_CAMERA_ACCESS_DISABLE:
                        set_camera_with_osd(camera_id, False)
        except OSError as e:
            if e.errno not in (errno.ENODEV, errno.EIO):
                log(f"read error: {e}")
            log("device went away, waiting for it to come back")
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
        time.sleep(2)


if __name__ == "__main__":
    sys.exit(main())
