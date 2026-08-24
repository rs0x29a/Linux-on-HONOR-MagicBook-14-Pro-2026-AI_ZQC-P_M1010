// SPDX-License-Identifier: GPL-2.0
/* EC-backed keyboard backlight for HONOR MagicBook Pro 14 2026 (ZQC-P). */
#include <linux/acpi.h>
#include <linux/dmi.h>
#include <linux/init.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/workqueue.h>

#define KBBL_OFFSET 0x41
#define KBBL_OFF    0x04
#define KBBL_LOW    0x02
#define KBBL_HIGH   0x03
#define KBBL_LATCH  0x01
#define LATCH_DELAY_MS 1500

static bool steady;
static enum led_brightness current = 1;
static struct delayed_work latch_work;

static u8 level_to_ec(enum led_brightness brightness)
{
	switch (brightness) {
	case 0:
		return KBBL_OFF;
	case 1:
		return KBBL_LOW;
	default:
		return KBBL_HIGH;
	}
}

static void latch_work_fn(struct work_struct *work)
{
	(void)work;
	ec_write(KBBL_OFFSET, KBBL_LATCH);
}

static int apply_level(enum led_brightness brightness)
{
	int ret;

	cancel_delayed_work_sync(&latch_work);
	ret = ec_write(KBBL_OFFSET, level_to_ec(brightness));
	if (!ret && steady && brightness > 0)
		schedule_delayed_work(&latch_work, msecs_to_jiffies(LATCH_DELAY_MS));
	return ret;
}

static int kbd_set(struct led_classdev *led, enum led_brightness brightness)
{
	(void)led;
	current = brightness;
	return apply_level(brightness);
}

static enum led_brightness kbd_get(struct led_classdev *led)
{
	(void)led;
	return current;
}

static ssize_t mode_show(struct device *dev, struct device_attribute *attr,
			 char *buf)
{
	(void)dev;
	(void)attr;
	return sysfs_emit(buf, "%s\n", steady ? "steady" : "reactive");
}

static ssize_t mode_store(struct device *dev, struct device_attribute *attr,
			  const char *buf, size_t count)
{
	(void)dev;
	(void)attr;
	if (sysfs_streq(buf, "steady"))
		steady = true;
	else if (sysfs_streq(buf, "reactive"))
		steady = false;
	else
		return -EINVAL;
	return apply_level(current) ? -EIO : count;
}

static DEVICE_ATTR_RW(mode);

static struct attribute *kbd_attrs[] = { &dev_attr_mode.attr, NULL };
ATTRIBUTE_GROUPS(kbd);

static struct led_classdev kbd_led = {
	.name = "huawei::kbd_backlight",
	.max_brightness = 2,
	.brightness = 1,
	.brightness_set_blocking = kbd_set,
	.brightness_get = kbd_get,
	.groups = kbd_groups,
	.flags = LED_CORE_SUSPENDRESUME,
};

static struct platform_device *kbd_pdev;

static const struct dmi_system_id honor_zqcp[] = {
	{ .matches = {
		DMI_MATCH(DMI_SYS_VENDOR, "HONOR"),
		DMI_MATCH(DMI_PRODUCT_NAME, "ZQC-P"),
	} },
	{ }
};

static int __init kbdlight_init(void)
{
	int ret;

	if (!dmi_check_system(honor_zqcp))
		return -ENODEV;
	INIT_DELAYED_WORK(&latch_work, latch_work_fn);
	kbd_pdev = platform_device_register_simple("honor-zqcp-kbdlight", -1,
						    NULL, 0);
	if (IS_ERR(kbd_pdev))
		return PTR_ERR(kbd_pdev);
	ret = led_classdev_register(&kbd_pdev->dev, &kbd_led);
	if (ret) {
		platform_device_unregister(kbd_pdev);
		return ret;
	}
	ret = apply_level(current);
	if (ret) {
		led_classdev_unregister(&kbd_led);
		platform_device_unregister(kbd_pdev);
		return ret;
	}
	pr_info("honor-zqcp-kbdlight: registered huawei::kbd_backlight\n");
	return 0;
}

static void __exit kbdlight_exit(void)
{
	cancel_delayed_work_sync(&latch_work);
	led_classdev_unregister(&kbd_led);
	platform_device_unregister(kbd_pdev);
}

module_init(kbdlight_init);
module_exit(kbdlight_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("EC keyboard backlight for HONOR ZQC-P");
