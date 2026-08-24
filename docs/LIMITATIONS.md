# What does not work, and why

Some of these are waiting on upstream, some are firmware decisions nobody
outside HONOR can change. Each says which.

| Limitation | Cause |
|---|---|
| **Caps Lock LED stays dark, below Linux 7.2** | `i8042.dumbkbd=1`, needed for the internal keyboard, also disables atkbd's `SET_LEDS` path, so the keyboard comes up without `EV_LED`. **Fixed upstream:** the `atkbd` DMI quirk for `ZQC-P` is in Linux **7.2** and queued for **7.1.10**. On such a kernel, drop the parameter and the LED comes back. See [`patch/keyboard-atkbd/`](../patch/keyboard-atkbd/) |
| **Fan speed cannot be set directly** | `SFNS` is gated on an `MFGM` flag no AML path ever sets; the DPTF `TFN1` cooling device accepts writes the EC ignores; `F0PD`/`F1PD` are read-only from AML; and `WTER` does not exist in this firmware. The measured early-engagement curves are now available through the opt-in [`patch/fan-curve/`](../patch/fan-curve/) controller, which forbids `0xAC` and restores stock `0xA0` on a thermal failsafe |
| **Mic-mute LED follows the built-in array only** | the kernel's control-LED group tracks `Dmic0 Capture Switch` and lights the LED only when *every* attached control is muted. Mute the 3.5 mm jack input while it is not the default and the LED does not move. The built-in array is the default, so Fn+F7 works normally. See [`patch/headset-mic/README.md`](../patch/headset-mic/README.md) |
| **Brightness steps are not perceptually uniform** | the desktop divides `max_brightness` linearly, 20 steps of 5% on this panel, so the first step changes the light output far more than the rest. [`patch/oled-backlight/`](../patch/oled-backlight/) removes the worst of it by raising the floor, but a perceptual curve has to come from the desktop, and PowerDevil rejected one by design |
| **The very dim end is not usable** | this OLED does not render its firmware-declared minimum evenly. Raising the floor trades the darkest settings for an even image; there is no setting that gives both |
| **Backlight PWM above roughly 15% brightness** | the panel's own 4320 Hz dimming, which HONOR advertises as flicker free, only runs at low brightness. Above it a low-frequency envelope from the SoC is all that remains, and it cannot be changed: the driver takes the PWM period from the `BXT_BLC_PWM_FREQ` register the BIOS programmed, consulting the VBT frequency field only when that register reads zero. **The figure here is 200 Hz, read out of that register.** Notebookcheck's instrumented review of the same panel reports 120 Hz worst case, with flicker detected at and below 85% brightness. Those are probably measuring different things, a programmed period against an observed optical modulation, but both numbers are in circulation |
| **MIPI / IPU6 cameras unconfigured** | no sensor on this SKU |
| **NFC unusable** | the `NTAG0001` controller sits on I²C-1 and Linux has no driver for it. It is also the device whose load-time GPIO call breaks the whole ACPI table, which [`patch/acpi-override/`](../patch/acpi-override/) exists to fix |
| **Keyboard backlight keys do nothing** | the keys arrive, but the WMI write path can fail with `-ENODEV`. The verified ZQC-P profile now has an **experimental, opt-in** EC driver using the DSDT's `KBBL` field at offset `0x41` with three levels. It still needs a physical test on the target unit. See [the dedicated fix](../patch/keyboard-backlight/README.md) and [the ZQC-P page](hardware/zqc-p.md#the-keyboard-backlight-is-reachable) |
| **Some OEM helper ACPI devices disabled** | `INTC10CC` HID Discovery, `INTC10DF` TSE and similar are disabled by firmware and are not needed for any user-visible function |

## Recovering the Caps Lock LED

Caps Lock itself works correctly as a modifier; only the LED is dark.

**On Linux 7.2, or 7.1.10 and later, just remove the parameter.** Your kernel
carries the `atkbd` DMI quirk for this machine and the keyboard works without
it. `uninstall_patch.sh` strips it, or edit the command line by hand:

```sh
sudo sed -i 's/ i8042\.dumbkbd=1//' /etc/default/limine   # or /etc/default/grub
sudo limine-update                                        # or update-grub
```

Then confirm, after rebooting:

```sh
grep -c i8042.dumbkbd /proc/cmdline     # 0
ls /sys/class/leds/ | grep capslock     # inputN::capslock
```

On an older kernel you can still try it, one boot at a time:

1. Reboot. At the bootloader menu, edit the kernel entry (`e` in Limine and in
   GRUB).
2. In the command line, strip ` i8042.dumbkbd=1`.
3. Boot. Plug in an external USB keyboard first, as a fallback in case the
   internal one misbehaves.
4. Use the internal keyboard for a few minutes. No key repeats, no dropouts and
   a working Caps Lock LED means your kernel has the quirk; remove the parameter
   permanently. Otherwise put it back.

> One report suggests `i8042.nomux=1` as a softer alternative that keeps the LED.
> **Nothing corroborates it.** It comes from a repository whose own description
> says it was AI-generated, where the option is only an `if` branch writing a
> different token, and its own notes admit the default is `dumbkbd`. It costs
> one reboot to try and it may simply not work.

There is no EC-side Caps Lock LED field in this BIOS: none of `CAPL`, `CAPS`,
`CapsLed` or `KBLE` appears in the disassembled DSDT. The LED is
keyboard-internal and only the PS/2 `SET_LEDS` command can drive it, which is
exactly what `i8042.dumbkbd=1` switches off.

---


## Cooling and fan behaviour

The fans work, but they engage far later than they do on Windows with HONOR PC
Manager. This is EC firmware behaviour and is not something this repo fixes.

| EC-CPU temp | fan 0 | fan 1 | |
|---|---|---|---|
| 49 °C, idle from a cold boot | 0 | 0 | genuinely stopped |
| 51-68 °C | 0 | 0 | still stopped, load already ramping |
| **72 °C** | **2355** | **1913** | **engagement point** |
| 84 °C | 2455 | 2373 | |
| 89 °C | 3656 | 3276 | clearly audible |

Two things surprise people: the fans are completely off at idle, and there is a
long spin-down hysteresis, so a non-zero reading at low temperature usually
means "recently under load" rather than "idle speed".

RPM readout is solved by `honor-ec-sensors`, and there is a second route: the
firmware's own `\GFNS` method, which an accepted upstream hwmon driver already
uses on a sibling HONOR. Control is not available by any route tried. The full
measurements, the EC register map, and every control path that was tested and
failed are in [`patch/fan/README.md`](../patch/fan/README.md).

---
