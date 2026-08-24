# Safe fan-curve control

The firmware does not accept a direct OS duty-cycle write: `SFNS`, DPTF and
the ACPI fan objects accept values but the EC ignores them. It does, however,
expose `IFCI`, which selects the EC's internal curve through `FTSL`.

This patch exposes the two measured early-engagement curves without shipping
the dangerous `0xAC` value, which disables both fans. It runs a small systemd
controller and reverts to stock `0xA0` at the configured temperature threshold
or when the service stops.

Install explicitly:

```sh
sudo FAN_CURVE=0xAA bash patch/fan-curve/install.sh
```

`0xA0` is stock; `0xAA` and `0xAB` engage the fans earlier. Manual PWM/RPM
control remains impossible on this firmware; this is the maximum safe control
surface currently exposed by the EC.

Check or reset:

```sh
sudo /usr/local/lib/honor/honor-fan-curve.sh status
sudo /usr/local/lib/honor/honor-fan-curve.sh reset
sudo systemctl disable --now honor-fan-curve.service
```
