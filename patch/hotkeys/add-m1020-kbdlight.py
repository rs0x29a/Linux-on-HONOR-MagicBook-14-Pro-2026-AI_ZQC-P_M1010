#!/usr/bin/env python3
import sys

path = sys.argv[1]
with open(path) as f:
    src = f.read()

if "HONOR_M1020_KBDLIGHT" in src:
    raise SystemExit("M1020 keyboard-backlight support is already present")
if "KBDLIGHT_MODE_GET" in src:
    raise SystemExit("this kernel already has another keyboard-backlight implementation; review it instead of stacking patches")

command_anchor = "\tMICMUTE_LED_SET"
pos = src.find(command_anchor)
if pos < 0:
    raise SystemExit("could not find the HWMI command enum")
end = src.find("\n", pos)
src = src[:end + 1] + (
    "\tKBDLIGHT_TIMEOUT_SET\t\t= 0x00001106,\n"
    "\tKBDLIGHT_TIMEOUT_GET\t\t= 0x00001206,\n"
    "\tKBDLIGHT_MODE_GET\t\t= 0x00001306,\n"
    "\tKBDLIGHT_MODE_SET\t\t= 0x00001406,\n"
) + src[end + 1:]

struct_anchor = "\tstruct led_classdev cdev;\n"
if struct_anchor not in src:
    raise SystemExit("could not find the huawei_wmi LED field")
src = src.replace(struct_anchor, struct_anchor +
                  "\tstruct led_classdev kbdlight_cdev;\n"
                  "\tbool kbdlight_available;\n", 1)

param_anchor = 'MODULE_PARM_DESC(report_brightness,\n\t\t"Report brightness keys.");\n'
if param_anchor not in src:
    raise SystemExit("could not find the huawei-wmi module parameters")
src = src.replace(param_anchor, param_anchor + (
    "\n#define HONOR_M1020_KBDLIGHT 1\n"
    "static int kbdlight_timeout = 15;\n"
    "module_param(kbdlight_timeout, int, 0444);\n"
    "MODULE_PARM_DESC(kbdlight_timeout, \"Keyboard backlight timeout in seconds; 0 disables it\");\n"
), 1)

led_anchor = "static void huawei_wmi_leds_setup(struct device *dev)\n"
if led_anchor not in src:
    raise SystemExit("could not find huawei_wmi_leds_setup")
code = r'''static int huawei_wmi_kbdlight_mode_get(int *level)
{
	u8 ret[0x100] = { 0 };
	int err;

	err = huawei_wmi_cmd(KBDLIGHT_MODE_GET, ret, sizeof(ret));
	if (err)
		return err;

	switch (ret[1]) {
	case 0x02:
		*level = 0;
		return 0;
	case 0x03:
		*level = 1;
		return 0;
	case 0x04:
		*level = 2;
		return 0;
	default:
		return -EIO;
	}
}

static int huawei_wmi_kbdlight_mode_set(int level)
{
	union hwmi_arg arg;

	if (level < 0 || level > 2)
		return -EINVAL;
	arg.cmd = KBDLIGHT_MODE_SET;
	arg.args[2] = level + 2;
	return huawei_wmi_cmd(arg.cmd, NULL, 0);
}

static int huawei_wmi_kbdlight_timeout_get(int *seconds)
{
	u8 ret[0x100] = { 0 };
	int err;

	err = huawei_wmi_cmd(KBDLIGHT_TIMEOUT_GET, ret, sizeof(ret));
	if (!err)
		*seconds = ret[1] | (ret[2] << 8);
	return err;
}

static int huawei_wmi_kbdlight_timeout_set(int seconds)
{
	union hwmi_arg arg;

	if (seconds < 0 || seconds > 0xffff)
		return -EINVAL;
	arg.cmd = KBDLIGHT_TIMEOUT_SET;
	arg.args[2] = seconds & 0xff;
	arg.args[3] = seconds >> 8;
	return huawei_wmi_cmd(arg.cmd, NULL, 0);
}

static int huawei_wmi_kbdlight_led_set(struct led_classdev *led_cdev,
		enum led_brightness brightness)
{
	int err;

	err = huawei_wmi_kbdlight_mode_set(brightness);
	if (!err && kbdlight_timeout >= 0)
		err = huawei_wmi_kbdlight_timeout_set(kbdlight_timeout);
	return err;
}

static ssize_t kbdlight_timeout_show(struct device *dev,
		struct device_attribute *attr, char *buf)
{
	int err, seconds;

	err = huawei_wmi_kbdlight_timeout_get(&seconds);
	if (err)
		return err;
	return sysfs_emit(buf, "%d\n", seconds);
}

static ssize_t kbdlight_timeout_store(struct device *dev,
		struct device_attribute *attr, const char *buf, size_t count)
{
	int err, seconds;

	if (kstrtoint(buf, 10, &seconds))
		return -EINVAL;
	err = huawei_wmi_kbdlight_timeout_set(seconds);
	if (err)
		return err;
	kbdlight_timeout = seconds;
	return count;
}
static DEVICE_ATTR_RW(kbdlight_timeout);

static bool huawei_wmi_kbdlight_is_m1020(void)
{
	return dmi_match(DMI_SYS_VENDOR, "HONOR") &&
		dmi_match(DMI_PRODUCT_NAME, "ZQC-P") &&
		dmi_match(DMI_PRODUCT_VERSION, "M1020") &&
		dmi_match(DMI_PRODUCT_SKU, "C170");
}

static void huawei_wmi_kbdlight_setup(struct device *dev)
{
	struct huawei_wmi *huawei = dev_get_drvdata(dev);
	int err, level;

	if (!huawei_wmi_kbdlight_is_m1020() ||
		!acpi_has_method(NULL, "\\GKBM") ||
		!acpi_has_method(NULL, "\\SKBM") ||
		!acpi_has_method(NULL, "\\GKBT") ||
		!acpi_has_method(NULL, "\\SKBT"))
		return;
	if (huawei_wmi_kbdlight_mode_get(&level))
		return;

	huawei->kbdlight_cdev.name = "platform::kbd_backlight";
	huawei->kbdlight_cdev.max_brightness = 2;
	huawei->kbdlight_cdev.brightness = level;
	huawei->kbdlight_cdev.brightness_set_blocking = huawei_wmi_kbdlight_led_set;
	huawei->kbdlight_cdev.flags = LED_CORE_SUSPENDRESUME | LED_BRIGHT_HW_CHANGED;
	err = devm_led_classdev_register(dev, &huawei->kbdlight_cdev);
	if (err)
		return;

	huawei->kbdlight_available = true;
	device_create_file(dev, &dev_attr_kbdlight_timeout);
	if (kbdlight_timeout >= 0)
		huawei_wmi_kbdlight_timeout_set(kbdlight_timeout);
}

'''
src = src.replace(led_anchor, code + led_anchor, 1)

setup_anchor = "\tdevm_led_classdev_register(dev, &huawei->cdev);\n"
if setup_anchor not in src:
    raise SystemExit("could not find mic-mute LED registration")
src = src.replace(setup_anchor, setup_anchor +
                  "\thuawei_wmi_kbdlight_setup(dev);\n", 1)

key_anchor = "\tkey = sparse_keymap_entry_from_scancode(idev, code);\n"
if key_anchor not in src:
    raise SystemExit("could not find hotkey dispatch")
notify = r'''	if (huawei_wmi->kbdlight_available && code >= 0x2b1 && code <= 0x2b3) {
		int level = code - 0x2b1;

		huawei_wmi->kbdlight_cdev.brightness = level;
		led_classdev_notify_brightness_hw_changed(
			&huawei_wmi->kbdlight_cdev, level);
		return;
	}
	if (huawei_wmi->kbdlight_available && (code == 0x2e5 || code == 0x2e6))
		return;

'''
src = src.replace(key_anchor, notify + key_anchor, 1)

with open(path, "w") as f:
    f.write(src)
