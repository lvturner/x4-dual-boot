#!/usr/bin/env bash
# Build the full 16 MB SPI flash image used by the CH341a/flashrom recovery path
# (see docs/RECOVERY-SPI.md). Run ./build-both.sh first so the firmware artifacts
# exist. Output: x4-dualboot-spi-flash.bin
set -euo pipefail
cd "$(dirname "$0")"

MS=microslate-firmware/.pio/build/xteink_x4
CI=crossink/.pio/build/default

for f in "$MS/bootloader.bin" "$MS/partitions.bin" "$MS/firmware.bin" "$CI/firmware.bin"; do
  [ -f "$f" ] || { echo "Missing $f — run ./build-both.sh first." >&2; exit 1; }
done

OUT=x4-dualboot-spi-flash.bin
rm -f "$OUT"

# Layout: MicroSlate bootloader (rollback off) + partitions + MicroSlate@app0 +
# CrossInk@app1. otadata (0xe000) is left empty so the bootloader boots app0.
python3 -m esptool --chip esp32c3 merge-bin --flash-mode dio --flash-size 16MB \
  -o "$OUT" \
  0x0      "$MS/bootloader.bin" \
  0x8000   "$MS/partitions.bin" \
  0x10000  "$MS/firmware.bin" \
  0x650000 "$CI/firmware.bin"

# Pad to the full 16 MB chip size with 0xFF so flashrom accepts it cleanly.
python3 - "$OUT" <<'PY'
import os, sys
p = sys.argv[1]
target = 16 * 1024 * 1024
with open(p, "ab") as f:
    f.write(b"\xff" * (target - os.path.getsize(p)))
print(f"{p}: {os.path.getsize(p)} bytes (0x{os.path.getsize(p):x})")
PY

echo
echo "Wrote $OUT."
echo "Flash with:  sudo flashrom --programmer ch341a_spi -w $OUT"
echo "(Read the chip twice and compare hashes first — see docs/RECOVERY-SPI.md)"
