# toco (Mi Note 10 Lite) port notes

Separate from NOTES.md (the sweet engineering log). Observations are marked
[obs], guesses [guess]. Sources: live device via adb, mainline DTS
(`research/mainline-dts/`, sm7150-mainline/linux tag v7.2, not committed).

## Device [obs 2026-11-12]
- toco_global, PixelOS 15 (`PixelOS_toco-15.0-20250518-2143`), vendor fingerprint MIUI V13.0.4.0.SFNMIXM (Android 12).
- 6 GB variant (MemTotal 5639012 kB). Not A/B. Panel 1080x2340, 440 dpi.
- Partitions include abl, boot, dtbo, vbmeta, persist, modemst1/2, fsg, fsc, splash, logo, super, userdata.
- adb non-root only (user build). /proc/cmdline not readable without root.
- No official OrangeFox for toco (API lists only sweet / tucana-unsupported).

## sweet -> toco differences (mainline DTS) [obs from DTS, unverified on hardware]
| Item | sweet | toco |
| --- | --- | --- |
| Framebuffer (cont_splash) | 0x9c000000, 1080x2400 | 0x9c000000, 1080x2340 (size 1080*2340*4 = 0x9a3f80) |
| rmtfs carve-out | 0xfde01000 +2M | **0xf5e01000** +2M |
| Touch | Goodix GT9896 @0x5d, i2c7 | **ST FTS @0x49, i2c7** (GT9886 @0x5d as alternative panel variant, commented) |
| Touch power | PM6150L LDO11 via RPMh | **fixed reg: TLMM GPIO72 (vin L10A 1.8V)** + avdd **L6C 3.0V** |
| Touch IRQ/reset | ? | IRQ TLMM GPIO9 (level low), reset GPIO8 |
| Panel | DSC video | visionox,g2647fb105 (+ lab/ibb) |
| Keys | gpio-keys in common dtsi | same common dtsi -> [guess] identical |
| adsp/tz/wlan/npu/ipa/gpu carve-outs | | identical addresses |

Consequences:
- Low-bank bring-up range from sweet (0xb0000000 + 0x4d000000 = up to 0xfd000000) **overlaps toco rmtfs at 0xf5e01000**.
  Low-bank MEM_SIZE must stay below 0xf5e01000 (max 0x45e00000) [guess]; prefer --highmem once
  the upper-bank layout of the 6 GB variant is known (/proc/iomem from recovery).
- Touch needs a new ST FTS protocol driver (patch 0063 is Goodix-only) and a GPIO-based rail instead of RPMh LDO11.
  First boots: `sweettouch=0`.

## Live measurements (TWRP recovery, adb root) [obs 2026-11-12]
- Recovery partition holds TWRP for toco (product twrp_toco, eng build, adb root). No OrangeFox needed.
- Backup: 14 partitions in backup/, SHA-256 verified against the device (backup/SHA256SUMS).
- /proc/iomem System RAM: 80000000-856fffff, 97f17000-9e3fffff, a1600000-aeffffff, b0000000-1fcbfffff.
  DT memory node = <0x80000000 +2G, 0x100000000 +0xfcc00000>: **identical to sweet** -> mkadt --highmem values unchanged.
  rmtfs is dynamically placed (reg = size only) on this firmware; with no Linux/modem running it is irrelevant for the shim.
- Splash (sde_kms): 0x9c000000 size 0x1700000, identical to sweet.
- Panel: `dsi_xiaomi_f4_41_06_0a_fhd_cmd_display` = **command mode** (sweet: DSC video mode).
- Touch: **ST FTS at 1-0049 is the live controller**; GT9886 probe "i2c test FAILED". FTS: irq GPIO9, reset GPIO8.
- PixelOS boot.img: header v2, one generic SDMMAGPIE dtb (board-id 0), os_version 15.0.0; toco overlay comes from dtbo.

## Hardware test 1: shim without payload [obs 2026-11-12]
- `SHIM_FB_H=2340 shim/build.sh` + `fastboot boot shim/out/shim-boot.img`: ABL boots it, **red screen with text visible**
  -> fb writes show on the command-mode panel without any MDP kick (ABL leaves autorefresh on) [guess for the mechanism].
- UFS probe (read-only) works unchanged: ver 0x210, LUN0 lastlba 0x1D7D7FF blk 0x1000, GPT ok.
  userdata lba 0x2B8200, 0x1AC55 MiB (~107 GiB). XNU patch 0028 finds userdata by GPT name -> fine.

## Open
- Recovery with adb root for toco (backup + /proc/iomem + live DTB).
- Which touch variant this unit has (FTS vs Goodix): check `/sys/bus/i2c/devices` / dmesg.
- CI: GitHub retired the `macos-14` runner (run 43296208733: "configuration 'macos-14-arm64-us-default' is not supported").
  Workflow needs an Xcode 15.x iig; check what macos-15 offers.
- Kernel hardcodes panel height 2400 in 0061 (IOMFB logical size/offset) and 0058 (touch Y normalisation).
  Fine for milestone 1 (rows 2340..2399 land inside the 0x1700000 splash region, just invisible); must come
  from the ADT `height` before the GUI milestone.
- First XNU boot without `ufsrw=1`: sweet_ufs is read-only, sweetlog thread does not start -> userdata untouched.

## Build recipe (toco)
```sh
python3 tools/mkadt.py shim/out/toco.adt --highmem --toco
python3 tools/mkpayload.py xnu/out/kernel.development.sweet shim/out/toco.adt shim/out/payload.bin --cmdline '...'
SHIM_FB_H=2340 shim/build.sh ../shim/out/payload.bin
```
