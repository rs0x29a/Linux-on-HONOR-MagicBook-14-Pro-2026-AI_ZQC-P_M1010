# Testing on a model nobody here owns

Most of the machines this repository recognises have never had a single fix run
on them. If you have one, an afternoon of your time moves it from "we know the
model exists" to "this works, here is what to install".

Nothing here asks you to trust the repository blindly. The installers refuse by
default on a board whose profile section is not `verified`, and the subset they
will run without that is deliberately limited to fixes that cannot carry another
machine's values.

Note the word **board**. HONOR ships one product code as several machines, so
what matters is `cat /sys/class/dmi/id/board_version`, not the name on the box.
A revision this repository has never seen is recognised and run at the lowest
trust rather than refused, and it never inherits a status somebody earned on a
different board.

---

## Before anything else: two dumps

Both are read-only and take a minute each.

```sh
sudo bash tools/collect-hwinfo.sh
sudo bash tools/dump-acpi.sh
```

The first produces a ~200 KB archive with your DMI, every PCI and USB device,
the HID and input devices, the backlight, and the kernel log. It never reads
the serial-number attributes and checks its own output for them before packing.

The second produces your ACPI tables, disassembled. That one matters if the
touchpad is missing: the fix for that is a corrected firmware table, and it has
to be built from *your* firmware.

Attach both to an issue using the "Hardware dump for a new model" template.
**Even if you stop reading here, that alone is worth doing** — it fills in most
of a device profile, and somebody else with the same laptop benefits.

---

## Then: what actually happens on your machine

The most useful thing you can tell us is not "it works" but *what it does*.
Please go through these and report what you see, including the boring answers.

### 1. Does it even boot and log in

| | |
|---|---|
| Does the internal keyboard work at the bootloader? At the login screen? | |
| Does the touchpad exist? `libinput list-devices \| grep -i touchpad` | |
| Is the NVMe drive visible to the installer? | |

If the keyboard is dead, try adding `i8042.dumbkbd=1` to the kernel command
line. Then tell us your kernel version, because the fix for this is now
upstream on a per-model basis: `FMB-P` and `FMB-PM` from 6.19, `BCC-N` from
7.1, `ZQC-P` from 7.2 and 7.1.10. If your model is one of those and the
parameter is still needed on a newer kernel than that, we want to know.

### 2. The ACPI table

```sh
journalctl -k -b | grep -iE "AE_AML_INTERNAL|table load|I2C_DEVT"
```

An `AE_AML_INTERNAL` while loading a table is the fault that hides the touchpad
on `ZQC-P`, `XWC-P`, `FMB-P` and `FMB-PM`. The 2024 machines, `DRA-XX` and
`DRB-P`, do **not** have it. Paste what you get, including nothing.

`ACPI Error: AE_NOT_FOUND, \_SB.PC00.I2C3.TPD0` is a different message and is
harmless: it appears on every machine in this family and refers to a device slot
your SKU does not populate. Do not confuse the two.

### 3. What the hotkeys do

```sh
sudo bash patch/hotkeys/capture-keys.sh
```

Press the whole F-row on its own and with Fn, plus the vendor key, the
performance-mode key, keyboard backlight, camera shutter and touchpad lock.
Then paste the report. It separates three cases that look identical from the
outside: the key reaches the driver unmapped, the key arrives as a proper event
that nothing acts on, and the key never leaves the embedded controller.

### 4. The battery limit

This one has a definite answer and takes two commands:

```sh
echo "70 90" | sudo tee /sys/devices/platform/huawei-wmi/charge_control_thresholds
sudo modprobe ec_sys
sudo python3 -c "print(hex(open('/sys/kernel/debug/ec/ec0/io','rb').read(0x100)[0x85]))"
```

A nonzero value from the last command means the EC armed its limiter and the
pair works. `0x0` means it stored the pair and ignored it. Try `40 70` and
`95 100` as well, and tell us which of the three your EC accepts.

If all three read `0x0`, try the request PC Manager makes, `\SBCM`, once:

```sh
echo 0x5a4648021503 | sudo tee /sys/kernel/debug/huawei-wmi/arg     # 70-90, mode 2
sudo cat /sys/kernel/debug/huawei-wmi/call > /dev/null
sudo cat /sys/kernel/debug/huawei-wmi/call > /dev/null              # twice, deliberately
sudo python3 -c "print(hex(open('/sys/kernel/debug/ec/ec0/io','rb').read(0x100)[0x85]))"
```

`0x2` now means your EC is like the ZQC-P `M1020`: it enforces the presets but
has to be told the mode once. Say so in the issue, and then repeat the first
test, because on that board the plain writes started arming afterwards. Why
that matters and what is known so far:
[`patch/battery/README.md`](../patch/battery/README.md).

### 5. The fans

```sh
sudo modprobe ec_sys
sudo python3 -c "
d=open('/sys/kernel/debug/ec/ec0/io','rb').read(0x100)
print('0x2c..0x2f:', ' '.join(f'{b:02x}' for b in d[0x2c:0x30]))"
```

Run it once cold and once after a few minutes of load. If the two 16-bit
little-endian words change with fan noise, your tachometers are at the same
offsets as ours. If they do not, they are somewhere else in that page and the
whole dump is worth sending.

### 6. Everything else

Speakers, internal microphone, headset jack, webcam, fingerprint reader,
Wi-Fi, Bluetooth, suspend, hibernate, external display over USB-C and HDMI.
For each: works, does not work, or works with something. "Works out of the box"
is a genuinely useful answer and is often missing from reports.

---

## Then, if you want to go further

With `ALLOW_UNVERIFIED=1` the installer will run the fixes that cannot go
wrong on unverified hardware:

```sh
sudo ALLOW_UNVERIFIED=1 ./apply_patch.sh
```

Read what it skips and why. Each refusal names the value that is missing, and
that list is precisely what the model still needs.

`uninstall_patch.sh` reverts all of it.

---

## What comes back to you

A dump and a filled-in report turn into a `[board ...]` section in a device
profile and a page under [`docs/hardware/`](hardware/) with your findings and
your name against them. If you then run the fixes and they work, that section
becomes `verified`, and the next owner of the same board gets the whole thing
working from one command.

If something breaks, say so plainly and it gets recorded as plainly. A page
that says "the fingerprint reader does not work and here is why" is worth more
than one that quietly omits it.
