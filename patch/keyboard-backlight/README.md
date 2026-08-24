# EC keyboard backlight

The ZQC-P exposes the keyboard backlight through EC field `KBBL` at offset
`0x41`. The driver presents it as the standard `huawei::kbd_backlight` LED with
off, low and high levels. It also supports `mode=reactive` and
`mode=steady` in the LED sysfs directory.

This is a model-specific, tier-B fix. It is not installed on another profile
until its EC mapping is measured there. The driver is deliberately separate
from `huawei-wmi`: the WMI method can report success while the EC remains
unchanged on this machine.

Test after installation:

```sh
ls -l /sys/class/leds/huawei::kbd_backlight
brightnessctl -d huawei::kbd_backlight set 1
brightnessctl -d huawei::kbd_backlight set 2
brightnessctl -d huawei::kbd_backlight set 0
```

If the kernel already exposes an LED with this name, the installer refuses to
load a duplicate. In that case collect `bash tools/doctor.sh --json` and use
the existing in-tree LED path instead.
