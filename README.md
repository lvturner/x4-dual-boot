# Xteink X4 Dual-Boot — MicroSlate + CrossInk

Run **MicroSlate** (distraction-free writer) and **CrossInk** (e-reader) on a single
**USB-locked Xteink X4**, switchable from either app's menu, installed entirely via
the **SD-card OEM bootloader recovery** (no USB serial required).

This is a meta-repo. The actual firmware lives in two forks, included as submodules:

| Submodule | Fork | What it adds over upstream |
|---|---|---|
| `microslate-firmware/` | [`lvturner/microslate-firmware`](https://github.com/lvturner/microslate-firmware) (fork of `Josh-writes/microslate-firmware`) | `esp_ota_mark_app_valid_cancel_rollback()` so it survives reboots when SD-installed; raw-otadata slot switch (bypasses `esp_image_verify`); "CrossInk" menu entry with confirmation |
| `crossink/` | [`lvturner/CrossInk`](https://github.com/lvturner/CrossInk) (fork of `uxjulia/crossink`) | `mark_valid` at boot; a **"MicroSlate"** entry on the root home menu (reuses CrossInk's `ota_boot::switchTo`) |

Both firmwares share the identical partition table (`app0` @ 0x10000, `app1` @ 0x650000,
6.25 MB each), so one app lives in each OTA slot.

---

## Why this exists

Some X4 units are **USB-locked**: the USB port is a fixed HID device (`5548:6674`)
with no CDC serial and no Espressif download mode. `esptool`, the Web Serial installer,
and `pio run -t upload` all fail. The only install path is the device's OEM bootloader
**SD-card recovery**: copy `update.bin` to the card, hold **power + up**.

Two problems then bite, and both forks fix them:

1. **Rollback.** A slot written by the OEM SD recovery boots once as "pending verify"
   and the bootloader **rolls back to the previous (stock) slot on the next reset**
   unless the app self-confirms via `esp_ota_mark_app_valid_cancel_rollback()`.
   Upstream MicroSlate and CrossInk don't call it → they boot once, then revert on
   every reboot / deep-sleep wake / Back-hold. Both forks add the call at the end of
   `setup()`.

2. **Slot switch can silently fail.** `esp_ota_set_boot_partition()` runs
   `esp_image_verify`, which rejects valid images with bogus eFuse-rev errors on
   these bootloaders. The switch is done by **writing otadata directly**
   (CrossInk's `ota_boot::switchTo`, ported into MicroSlate), which bypasses that.

The OTA/rollback mechanism was reverse-engineered and documented by the CrossPoint
project — see [`crosspoint-reader/crosspoint-tools`](https://github.com/crosspoint-reader/crosspoint-tools)
(`INTEGRATION.md`).

---

## Prerequisites

- Python 3 + PlatformIO: `pip install --user platformio`
- ~5 GB free disk (ESP-IDF toolchain for MicroSlate + Arduino-ESP32 for CrossInk)
- Linux x86_64 or Windows (the ESP-IDF toolchain does not support Mac ARM / Pi)
- A **FAT32** MicroSD card and a USB cable for power

> **Fedora Silverblue / Kinoite / distrobox** (where `/home` is a symlink):
> MicroSlate's ESP-IDF-from-source build hits a PlatformIO path-collision bug.
> Run `microslate-firmware/scripts/fix-platformio-home-symlink.sh` first (idempotent).
> CrossInk uses the Arduino framework and is unaffected.

---

## Build

```bash
git clone --recursive https://github.com/lvturner/x4-dual-boot
cd x4-dual-boot
./build-both.sh
```

This produces two **pure OTA app images** (the exact format the OEM SD recovery expects):

- `microslate-update.bin`  (~1.7 MB)
- `crossink-update.bin`    (~6.3 MB)

Each project's `pio run` output is already an OTA app image — no extraction/conversion
needed, just rename to `update.bin` on the SD card.

---

## Flash (two SD flashes — order matters)

The OEM SD recovery always writes the *inactive* slot and switches to it. Flashing
**CrossInk first, then MicroSlate** leaves **MicroSlate active** with CrossInk in the
other slot, regardless of starting state.

1. **CrossInk** — copy `crossink-update.bin` to the SD card root as **`update.bin`**,
   plug in, hold **power + up**. Wait for the CrossInk home screen (so `mark_valid`
   runs and locks the slot).
2. **MicroSlate** — copy `microslate-update.bin` to the SD card as **`update.bin`**,
   hold **power + up**. MicroSlate writes the other slot and becomes active.

End state: MicroSlate is active; CrossInk is in the other slot.

### Updating an app later — read this first

The OEM SD recovery **always writes the inactive slot**. That has a trap: if you've
switched to app *X* and then flash *X*, the inactive slot is the **other** app, so
you'll **overwrite the other app with X** (ending up with two copies of X). This is
also what happens if you re-flash from a state you didn't set up.

Two safe ways to update:

- **Foolproof — re-run the 2-flash install above** (CrossInk then MicroSlate). From any
  state it rewrites one slot with CrossInk and the other with MicroSlate, leaving
  MicroSlate active. Use this if anything ever looks wrong.
- **Update one app only** — first **switch to the *other* app** (so the target app's
  slot becomes the inactive one), *then* flash the target. Example: to update MicroSlate
  while keeping CrossInk, switch to CrossInk first, then flash `microslate-update.bin`.

---

## Switching

- **MicroSlate → CrossInk:** main menu → the entry below *Sync* labelled **"CrossInk"**
  → Enter → confirm. MicroSlate writes otadata and reboots into CrossInk.
- **CrossInk → MicroSlate:** root home menu → **"MicroSlate"** → confirm → reboots
  into MicroSlate.

Both directions write otadata as a "pending" entry; the booted app marks itself valid
on the next boot, so the switch survives further reboots and deep-sleep.

---

## Troubleshooting

- **An app reverts to stock after a reboot** — `mark_valid` didn't run. Re-flash that
  app and let it fully reach its home/main screen before power-cycling.
- **A switch appears to do nothing** — re-flash the intended-primary app via SD; that
  rewrites the inactive slot and becomes active.
- **MicroSlate labels the other app `OTA Slot N`** — cosmetic; it can't read CrossInk's
  name. This fork overrides it to "CrossInk".
- **No USB serial at all** — expected on USB-locked units (HID bridge). There is no
  serial console; the SD path is the only way on or off the device.

---

## Recovery (if the device gets stuck)

If both slots ever end up holding the same app and the SD-card recovery stops landing
the other app (it flashes but boots back to the stuck app), the software paths are
exhausted — there's no USB serial to debug and no in-app way to write firmware. The
reliable recovery is to overwrite the full flash via an external SPI programmer
(CH341a + SOIC8 clip), which also swaps in a bootloader with OTA rollback disabled.

Full steps, image layout, and `build-spi-image.sh` are in
**[`docs/RECOVERY-SPI.md`](docs/RECOVERY-SPI.md)**.

---

## Credits

- MicroSlate — [`Josh-writes/microslate-firmware`](https://github.com/Josh-writes/microslate-firmware)
- CrossInk — [`uxjulia/crossink`](https://github.com/uxjulia/crossink) (a fork of CrossPoint)
- CrossPoint — [`crosspoint-reader/crosspoint-reader`](https://github.com/crosspoint-reader/crosspoint-reader)
  and the OTA reverse-engineering in [`crosspoint-reader/crosspoint-tools`](https://github.com/crosspoint-reader/crosspoint-tools)

Each firmware retains its upstream license; see the submodules.
