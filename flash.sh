#!/usr/bin/env bash
# Build a full 8 MiB SPI-NOR image for the TL-MR6400 v5 (raw-FIT layout):
#   0x000000  bootloader  (U-Boot SPL, from uboot-mediatek build)
#   0x040000  firmware    (FIT kernel + squashfs, the sysupgrade.bin)
#   0x7ff000  factory     (4 KiB MAC + WiFi cal blob)
# Run from the openwrt build root, in the shell that has flashrom + the build.
set -euo pipefail
cd ~/openwrt

OUT=/tmp/mr6400v5_full.bin
SPL=$(find . -path '*image*' -name 'mt7628_tplink_tl-mr6400-v5*u-boot-with-spl.bin' | head -1)
SYS=$(ls bin/targets/ramips/mt76x8/*-mr6400-v5-ubootmod-squashfs-sysupgrade.bin | head -1)
FAC=$PWD/mr6400v5_factory_repacked_4k.bin

echo "SPL : $SPL"
echo "SYS : $SYS  ($(stat -c%s "$SYS") bytes)"
echo "FAC : $FAC"
[ -n "$SPL" ] && [ -f "$SYS" ] && [ -f "$FAC" ] || { echo "MISSING INPUT"; exit 1; }

# sysupgrade must fit in the firmware window (0x040000..0x7ff000 = 0x7bf000 = 8121344 B)
SYSZ=$(stat -c%s "$SYS")
[ "$SYSZ" -le $((0x7bf000)) ] || { echo "FIRMWARE TOO BIG: $SYSZ > $((0x7bf000))"; exit 1; }

# 8 MiB of 0xff
dd if=/dev/zero bs=1M count=8 2>/dev/null | tr '\000' '\377' > "$OUT"
# bootloader @ 0x0
dd if="$SPL" of="$OUT" conv=notrunc
# firmware @ 0x040000  (block 64 of 4096)
dd if="$SYS" of="$OUT" bs=4096 seek=64 conv=notrunc
# factory @ 0x7ff000   (block 2047 of 4096)
dd if="$FAC" of="$OUT" bs=4096 seek=2047 conv=notrunc

[ "$(stat -c%s "$OUT")" -eq 8388608 ] && echo "SIZE_OK -> $OUT" || { echo SIZE_BAD; exit 1; }
echo "verify factory MAC in image:"
python3 -c "d=open('$OUT','rb').read(); print(':'.join('%02x'%b for b in d[0x7ff000:0x7ff006]))"
echo
echo "flash with:"
echo "  flashrom -p ch341a_spi -c W25Q64BV/W25Q64CV/W25Q64FV --write $OUT"
