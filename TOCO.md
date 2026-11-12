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

## Open
- Recovery with adb root for toco (backup + /proc/iomem + live DTB).
- Which touch variant this unit has (FTS vs Goodix): check `/sys/bus/i2c/devices` / dmesg.
- CI: GitHub retired the `macos-14` runner (run 43296208733: "configuration 'macos-14-arm64-us-default' is not supported").
  Workflow needs an Xcode 15.x iig; check what macos-15 offers.
