#!/usr/bin/env bash
# Build both dual-boot firmwares (MicroSlate + CrossInk) and stage them as
# pure OTA app images ready for the OEM SD-card recovery (rename to update.bin).
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Initialising submodules (crossink has its own: freeink-sdk)..."
git submodule update --init --recursive

echo
echo "==> Building MicroSlate (env: xteink_x4, ESP-IDF from source)..."
(
  cd microslate-firmware
  # Fedora Silverblue / distrobox (symlinked /home) needs this before the first build.
  if [ -x scripts/fix-platformio-home-symlink.sh ]; then
    ./scripts/fix-platformio-home-symlink.sh || true
  fi
  pio run
)
cp microslate-firmware/.pio/build/xteink_x4/firmware.bin microslate-update.bin

echo
echo "==> Building CrossInk (env: default, Arduino framework)..."
(
  cd crossink
  pio run -e default
)
cp crossink/.pio/build/default/firmware.bin crossink-update.bin

echo
echo "Done. Copy each file to the SD card root as 'update.bin' and flash with power+up:"
echo "  1) crossink-update.bin   (flash first)"
echo "  2) microslate-update.bin (flash second -> MicroSlate becomes active)"
echo
ls -l microslate-update.bin crossink-update.bin
