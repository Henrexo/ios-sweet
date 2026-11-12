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

## CI [obs 2026-11-12]
- macos-14 runner retired; xnu.yml now takes input `runner` (default macos-15). Run 43296813137 on macos-15 picked
  the oldest Xcode (16.0, 16A242d) and **succeeded**: all 81 patches applied, no compile errors, iig .cpp compiled.
  (NOTES.md says Xcode 16 iig is incompatible; not observed here - DriverKit RPC paths are untested on device.)

## Hardware test 2: first XNU boot (milestone 1 reached) [obs 2026-11-12]
- Image: upstream kernel (run 43296813137) + `mkadt --highmem --toco` + shim SHIM_FB_H=2340,
  cmdline `debug=0xc serial=3 cpus=1 keepsyms=1 -enable_kprintf_spam -noprogress rd=ufsroot0 wdt=-1
  wdt_test=no_user_checkin sweettouch=0 sweetkeys=0` (no ufsrw -> userdata untouched).
- Kernel console on screen; boots through IOKit/BSD: `SWEET FB: AppleCLCD 1080x2340 stride 4320 at 0x9c000000,
  presented as 1125x2436`, `SWEET CPU: 1/1 CPUs initialized, SGI1 verified`, Skywalk self-tests PASSED,
  `SWEET UFS: "userdata" on LUN 0: first block 0x2b8200, 109653 MiB, read-only`, DWC3/QUSB2 registers readable.
- Root mount loops as expected: `hfs_ValidateHFSPlusVolumeHeader: unknown Volume Signature`, `mount(N) failed`
  (userdata still holds Android).
- => CPU, RAM (highmem), GIC IRQs, timer, framebuffer, UFS identical to sweet in practice.

## Root image + first iOS boot [obs 2026-11-12]
- Fedora's apfs-fuse (snapshot 2020-09-28) has no LZBITMAP: rsync got EIO on 136785 files of the 16.7.16 OS image.
  Built upstream sgan81/apfs-fuse 66b86bd (2023-03, LZBITMAP since d24adbe) with GCC 16
  (`cmake -DUSE_FUSE3=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_CXX_FLAGS='-include cstdint'`)
  -> ~/.local/bin/apfs-fuse-lzbitmap, used via `APFS_FUSE=` (tools/mkiosroot.sh). 0 read errors.
- mkiosroot's final `fsck.hfsplus -f -n` reported "Volume header needs minor repair" (exit 8) right after a
  successful -y repair; after tweaks + `fsck -fy` the volume "appears to be OK". Used 12G of 16G, simg 12.1 GB.
- sweet-root-tweaks: "warning: no mobileactivationd system container in the image; skipped data ark".
- Flash: `-S 512M` -> ABL hung on block 1/24 (no OKAY). After a forced restart, `-S 256M`: 47/47 OKAY in 303 s.
  ABL hung again afterwards (getvar timeout); the forced restart gave USB enumeration errors (-71) until replug.
- Boot `shim/out/shim-boot-toco2.img` (cmdline = README full args + `sweettouch=0`, cpus=6) at 22:07:05:
  **Apple logo visible** (user report).

## Boot 2 analysis (log logs/toco-boot2.txt, pulled via TWRP after ~10 min on the Apple logo) [obs]
- 6/6 CPUs up, UFS read-write, sweetlog active, `SWEET FB: display on`, 7 swaps (boot logo). Keys work unchanged
  (power = key0 -> HID 0x30, vol-up = key1 -> 0xe9). Only crash: driverkitd (sig 9). bluetoothd/fairplayd relaunch loop.
- SpringBoard main thread identical in all 6 samples (>= 7.5 min, sampler every 90 s), symbolicated
  (ipsw dyld a2s, slide 0x27208000): __ulock_wait <- os_unfair_lock_lock_slow <- _LSContextInitCommon <-
  -[LSApplicationRecord initWithBundleIdentifier:allowPlaceholder:error:] <- -[CCSModuleRepository
  _queue_filterModuleMetadataByAssociatedBundleAvailability:] <- -[CCSModuleRepository _initWithDirectoryURLs:...].
  Another SpringBoard thread is inside _LSContextInitCommon (XPC to lsd). lsd exec 1x, no crash.
  [guess] lsd builds its database on first boot (CPU only) or is stuck. Not described in NOTES.md for sweet.
- Boot 3 (22:19:31, shim-boot-toco3.img): same args + `sweetsample=SpringBoard,lsd sweetnull=backboardd,lsd`.

## Boot 3 analysis (logs/toco-boot3.txt) [obs]
- lsd completely static over 5 samples. Symbolicated (lsd slide 0x1f4c000):
  t3 `__LAUNCH_SERVICES_CLIENTS_ARE_WAITING_FOR_THE_DATABASE_TO_FINISH_SEEDING__` (XPC from SpringBoard),
  t0 `-[_LSInstallProgressService performJournalRecovery]` (dispatch_sync), t2 `restoreInactiveInstalls` (group wait),
  t1 semaphore wait in libMobileGestalt <- `_GenerateBuiltInAppInstallSessionID` <- `+[MIInstallationIdentity
  installationIdentityForBundle:settingIfNotSet:error:]` <- `-[MIInstalledInfoGatherer _populatePlaceholderRecordValues:...]`.
- `_GenerateBuiltInAppInstallSessionID` = `MGCopyAnswer(@"re6Zb+zwFKJNlkQTUeT+/w")` = **UniqueDeviceID**.
- Our ADT has none of the syscfg identity iBoot fills into the D22AP template (root serial-number,
  mlb-serial-number, model-number, region-info; /chosen mac-address-bluetooth0/ethernet0).
  [guess] UDID computation blocks on one of those.
- Fix attempt (mkadt --toco): synthetic serial-number TOCO00000001, mlb TOCOMLB000000001, model MQAC2, region LL/A,
  /chosen mac-address-wifi0/bluetooth0/ethernet0 02:54:f0:c0:00:01..03. Boot 4 at 22:35:25 (shim-boot-toco4.img).

## MILESTONE: iOS lock screen on toco (boot 4, 2026-11-12 ~22:37 local) [obs]
- shim-boot-toco4.img (mkadt --highmem --toco incl. synthetic serial/MAC identity), image ios16-root-toco.
- Photo PXL_20261112_213713355.jpg: lock screen "Wednesday, December 31" 4:01, charging icon, camera button.
  ~2 min after `fastboot boot` (first boots without the identity props hung >10 min in lsd).
- => the UniqueDeviceID/identity fix resolved the LaunchServices seeding hang.
- Not working yet: touch (ST FTS, sweettouch=0), wall clock (no RTC), panel height 2400 hardcoded in 0058/0061.

## Touch driver (patch 0082) [2026-11-12]
- Live DT (TWRP): fts@49 on i2c@a84000 (SE7), pins gpio6/7 qup11, reset gpio8, irq gpio9 = same as sweet.
  vdd-supply = TLMM GPIO72 fixed reg "disp_vddio_vreg" (shared with panel VDDIO -> never toggled),
  avdd-supply = L6C (rpmh ldoc6, pm6150l_l6, 1.65..3.1 V, = vddpx_2 SD I/O); mainline uses 3.0..3.1 V -> 3000 mV.
- Protocol from MiCode/Xiaomi_Kernel_OpenSource toco-q-oss drivers/input/touchscreen/fts_521 (research/xiaomi-fts).
- 0082: sweet_touch.c gets a TOUCH_STFTS path behind boot-arg `sweettouchfts=1` (sweet unchanged);
  sweet_rpmh.c also accepts ldoc6 3000..3100 mV. Host syntax check with stub headers clean. CI run 43313281817.

## BLOCKER since ~22:55: ABL fastboot downloads fail [obs 2026-11-12 23:15]
- Kernel with 0082 built (CI 43313281817, xnu/out-0082), image shim/out/shim-boot-toco5.img (sweettouchfts=1) - never booted.
- Symptoms: getvar answers random (`product: toco` / 'unknown command' / 'GetVar Variable Not found',
  ~5-10 % wrong, mostly first queries after a pause); `fastboot boot` and even `fastboot stage` of 1 MB hang in the
  data phase. `fastboot reboot bootloader` once landed in TWRP. adb in TWRP works (4 MiB log pull fine).
- Ruled out: battery (51 %, charging), partitions (all backed-up partitions identical except modemst1/2 =
  valid EFS written by the modem under Android, persist = clean ext4, mount count 48->57 from Android/TWRP),
  misc BCB empty, cable/plug orientation, both laptop ports, host autosuspend (power/control=on did not fix;
  udev rule /etc/udev/rules.d/51-fastboot-nosuspend.rules did not apply on replug), ModemManager (no log),
  phone cold boot, no host package changes since 20:30.
- Started right after a background loop polled `fastboot getvar` every 3 s while ABL came up (22:55).
  Lesson: no polling loops against ABL/adb while booting.
- Next: reboot the PC (xhci state after the -71 error storm), then retry `fastboot stage` 1 MB, then boot toco5.

- 23:2x after PC reboot + new cable: `fastboot stage` 1 MB still hangs; ABL then crashed/rebooted into charger mode
  (05c6:f000). Host logs no USB errors -> phone-side ABL problem, cause unknown.
- WORKAROUND (user approved, deviates from CLAUDE.md "never flash shim"): shim written to `boot` from TWRP
  (`dd of=/dev/block/by-name/boot`, sha256 verified). Normal power-on boots iOS. Restore: dd backup/boot.img
  (sha 2bebd50a…, verified identical to device before the write). TWRP (recovery partition) untouched.
- 23:23:31 boot of shim-boot-toco5.img (touch 0082, sweettouchfts=1) from boot partition.

## Next
1. Touch (in progress, see above): ST FTS (FTM5) driver on GENI I2C SE7 @0x49, IRQ TLMM GPIO9, reset GPIO8, rails GPIO72 + L6C (patch 0063 is Goodix).
2. Panel height from ADT in 0061/0058 (2340).
3. Optional: RTC (PM6150 RTC over SPMI) for the clock.

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
