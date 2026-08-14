# SPI Flash Recovery (un-brick / last resort)

This is the recovery path for when the device is **stuck on MicroSlate and nothing
else can be flashed onto it**:

- both OTA slots contain MicroSlate,
- the OEM **SD-card recovery (power + up)** engages (screen flashes) but never boots
  the newly-written app — it always falls back to MicroSlate,
- there is **no USB serial** (the X4's USB is a fixed HID bridge, `5548:6674`,
  so `esptool`/Web Serial can't see it),
- the device **must not be opened destructively** — but see below, the SPI method
  is reversible.

If any of those is false, use the normal SD-card install in the main README instead.
This page is the last resort.

## Root cause (why you're stuck)

The stock bootloader has **OTA app-rollback** enabled. A slot written by the SD-card
recovery boots once as "pending verify" and **rolls back to the previous slot** unless
the freshly-booted app self-confirms via `esp_ota_mark_app_valid_cancel_rollback()`.
After repeated slot-switching the otadata ends up in a state where the bootloader
keeps selecting the MicroSlate slot, so nothing else can stick — and there's no serial
log to diagnose further. The fix is to **replace the bootloader** with one that has
rollback disabled (MicroSlate's), which removes the trap entirely.

## The recovery: overwrite the whole flash via SPI

You bypass USB, the bootloader, and the OS entirely by writing a full flash image
directly to the SPI flash chip with an external programmer.

### Tools

- **CH341a** USB SPI programmer + a **SOIC8 test clip** (~$5–10 total, e.g. search
  "CH341a 1.8V/3.3V SPI flasher with SOIC8 clip"). Set its voltage jumper to **3.3 V**.
- A small Phillips/jeweler's screwdriver, acetone (nail-polish remover), and a thin
  non-conductive prying tool.
- `flashrom` installed on your PC (`sudo dnf install flashrom` / `apt install flashrom`).

### The image

A ready-made 16 MB image is produced by **`./build-spi-image.sh`** in this repo (run
`./build-both.sh` first so the firmware artifacts exist). It lays out:

| Offset | Contents |
|---|---|
| `0x0` | **MicroSlate bootloader** (rollback **disabled** — this is the fix) |
| `0x8000` | partition table (app0 + app1, 6.25 MB each) |
| `0x10000` | MicroSlate app (app0 — boots first) |
| `0x650000` | CrossInk app (app1) |
| `0xe000` | otadata = empty → bootloader boots app0 (MicroSlate) |

Output file: `x4-dualboot-spi-flash.bin` (exactly 16 MB / `0x1000000`, padded `0xFF`).

### Physical prep

Follow CrossPoint's photo-illustrated guide step-by-step:
**<https://github.com/crosspoint-reader/crosspoint-reader/blob/develop/docs/fix-bricked-xteink.md>**

In short: remove the SD card and USB; disconnect the battery (cut one wire, tape the
end); keep the **Reset button held** (so the ESP32-C3 doesn't interfere with SPI);
clip the SOIC8 clip onto the flash chip with **pin 1 (red wire) on the dot**; set the
programmer to **3.3 V**; only then plug the programmer into the PC. The screen is
removed with acetone softening the adhesive (~2 h) — it is glued, not destroyed, and
reconnects via a flip ZIF connector, so this is reversible.

### Read → verify → write

With the clip attached and Reset held:

```bash
# 1. Read the chip TWICE and confirm the hashes match (bad clip = bad data).
sudo flashrom --programmer ch341a_spi -r read_0.bin
sudo flashrom --programmer ch341a_spi -r read_1.bin
sha256sum read_0.bin read_1.bin     # must be identical

# 2. Write the recovery image.
sudo flashrom --programmer ch341a_spi -w x4-dualboot-spi-flash.bin
# expect: "Verifying flash... VERIFIED."
```

### Reassemble & boot

Disconnect the programmer, remove the clip, release Reset, reinsert the SD card,
reconnect the screen, apply USB power, hold power ~2 s. **MicroSlate** should boot.
From MicroSlate, select the **"CrossInk"** entry to verify the dual-boot switch works.

## Trade-offs (read before writing)

- This **replaces the stock bootloader** (we don't have a stock-bootloader dump to
  preserve it). The OEM **power+up SD-card recovery will no longer work** afterward.
  That bootloader's rollback logic is precisely what bricked you, so removing it is
  the fix — but future firmware changes must be done via SPI again (you'll have the
  programmer) or by the in-app slot switch.
- The X4 has **no flash encryption / secure boot** (the CrossPoint SPI guide writes
  plain images successfully), so a plaintext image writes and boots fine.

## Layout / partition reference

```
0x000000  bootloader            (MicroSlate, rollback off)
0x008000  partition table
0x009000  nvs          (0x5000)
0x00e000  otadata      (0x2000)  ← empty (0xFF) in this image
0x010000  app0 / ota_0 (0x640000) MicroSlate
0x650000  app1 / ota_1 (0x640000) CrossInk
0xc90000  spiffs       (0x360000)
0xff0000  coredump     (0x10000)
0x1000000 end (16 MB)
```
