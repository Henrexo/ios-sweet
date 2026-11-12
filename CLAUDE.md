# Projekt: ios-sweet → Xiaomi Mi Note 10 Lite (toco) portieren

Übergabe aus einem claude.ai-Chat (12.11.2026). Diese Datei ins Root des eigenen ios-sweet-Forks legen.

## Ziel
iOS 16.7.16 (iPhone X, iPhone10,3, Build 20H392) per ios-sweet (github.com/dipa-studio/ios-sweet) auf einem
Xiaomi Mi Note 10 Lite (Codename `toco`, Snapdragon 730G / SM7150) booten. Erster Meilenstein: XNU-Kernel-Panic
sichtbar auf dem Display (= CPU, RAM, IRQs, Framebuffer laufen). Zweiter: Lock-/Home-Screen.

## Ausgangslage
- Gerät: Mi Note 10 Lite, Bootloader entsperrt, aktuell Pixel Experience installiert.
- Vorlage: ios-sweet läuft auf Redmi Note 10 Pro (`sweet`, Snapdragon 732G, ebenfalls SM7150). Gleiche SoC-Familie →
  GIC, Timer, PSCI, CPU-Cluster, wahrscheinlich UFS-Controller identisch.
- Einen fertigen toco-Fork gibt es (Stand 12.11.2026) nicht.
- Henry: FISI-Azubi, technisch fit, möchte auf Deutsch, direkt und mit konkreten Befehlen angesprochen werden.

## Arbeitsweise / Rollenverteilung
- Claude führt adb/fastboot/Build-Befehle selbst aus.
- Henry macht nur Physisches: Tasten drücken (Power + Leiser = Fastboot), Kabel, und berichtet bzw. fotografiert,
  was auf dem Display steht. Claude kann das Display NICHT sehen → nach jedem Boot fragen.
- Nach großem `fastboot flash` hängt Xiaomi-ABL-Fastboot oft → Henry muss Fastboot per Hand neu betreten.
  Keine Befehle gegen ein hängendes ABL wiederholen.
- Linux-Host: Debian/Ubuntu-VM auf Proxmox, Handy per USB-PORT-Passthrough (nicht per Vendor/Product-ID, weil
  sich die ID zwischen Android/Recovery/Fastboot ändert).

## Sicherheit / Rollback
- ios-sweet schreibt NUR `userdata`; Shim wird per `fastboot boot` gestartet, nie geflasht.
- Kernel schreibt einen 4-MiB-Log-Ring ans Ende von userdata → ab dem ersten Shim-Boot userdata als verloren betrachten.
- VOR allem anderen Backup (via temporär gebootetem OrangeFox für toco, adb root):
  persist, modemst1, modemst2, fsg, fsc, boot, dtbo, vbmeta → `backup/` (nicht committen).
- Rollback: Fastboot → `fastboot -w` → Pixel Experience neu flashen.

## Sweet-spezifische Werte, die für toco neu ermittelt werden müssen
Aus README "Key hardware facts" und `tools/mkadt.py`:
- RAM: `PHYS_BASE=0xb0000000`, `MEM_SIZE=0x4d000000`, `HIGH_PHYS_BASE=0x100000000`, `HIGH_MEM_SIZE=0xfcc00000`
  (obere DDR-Bank ~3,95 GiB) → toco: `/proc/iomem` + DT-`memory`-Node (6/8-GB-Variante beachten).
- Framebuffer: `FB=0x9c000000`, `FB_SIZE=0x1700000`; Panel 1080×2400 DSC Video-Mode, Continuous Splash vom ABL
  → toco: Panel ~1080×2340, Splash-Region aus DT (`cont_splash`/`splash_region`), Panelname aus `/proc/cmdline`.
  Auch `/chosen/display-scale` (3) und `sweetfb_hz` prüfen.
- GIC: `GICD=0x17a00000`, `GICR=0x17a60000` (SoC, vermutlich identisch). UFS `0x01d84000` (vermutlich identisch).
- Touch: Goodix GT9896 an I²C 0x5d auf QUP SE7 (0xa84000), Strom PM6150L LDO11 via RPMh
  → toco: Controller unbekannt, aus DT/`/sys/bus/i2c/devices`/dmesg bestimmen. Wenn kein Goodix: neuer Treiber nötig.
- Tasten: Power + Leiser über PM6150-PON, Lauter über PM6150L GPIO2 (SPMI SID 4) → toco: DT `gpio-keys` prüfen.
- Relevante Kernel-Patches: 0003/0010 (Framebuffer), 0028/0030/0034/0069 (UFS), 0060/0062/0063 (Tasten/Touch/RPMh),
  0072–0081 (USB/ECM). Engineering-Log: `NOTES.md` zuerst komplett lesen.
- Hilfreiche Vergleichsquelle: Mainline-DTS `sm7150-xiaomi-toco.dts` vs. `sm7150-xiaomi-sweet.dts`
  (github.com/sm7150-mainline/linux).

## Phasen
0. Linux-VM einrichten: gcc-aarch64-linux-gnu, mkbootimg, apfs-fuse, hfsprogs, img2simg, adb, fastboot, dtc, gh, ipsw.
   Repo forken (Kernel baut über GitHub Actions macOS-Runner, Workflow `xnu.yml`). IPSW iPhone10,3 16.7.16 von Apple laden.
1. Backup (siehe oben) + Hardware-Infos sammeln in Recovery:
   `/proc/iomem`, `/proc/interrupts`, `/sys/bus/i2c/devices`, `/proc/cmdline`, `dmesg`;
   DTB: `python3 tools/unpack_bootv2.py backup/boot.img dtb/boot_unpacked` → `dtc -I dtb -O dts`.
   Unsicher: ob PE-boot.img-DTB reicht, sonst boot.img aus MIUI-Fastboot-ROM nehmen.
2. Diff sweet ↔ toco, Werte in mkadt.py und Patches anpassen (am besten als eigene `toco`-Konstanten/Patches).
3. Kernel bauen: `gh workflow run xnu.yml -R <fork>` → `gh run download <id> -n xnu-kernel -D xnu/out`.
   Kernel-only-Änderungen vorher mit `tools/qemu-sweet.py` testen.
4. Erster Boot OHNE Root-Image: mkadt → mkpayload mit
   `rd=ufsroot0 cpus=1 wdt=-1 wdt_test=no_user_checkin sweettouch=0 sweetkeys=0` → shim/build.sh → `fastboot boot`.
   Erfolg = Panic auf dem Display (kein Root). Schwarz = Framebuffer/RAM falsch → Log über Recovery ziehen.
5. Root-Image: `tools/mkiosroot.sh` → fsck → mount → `sweet-root-tweaks.py` → img2simg →
   `fastboot -S 512M flash userdata ios16-root.simg` (~7 min, userdata ≥ 16 GB prüfen) → `fastboot boot` Shim
   mit vollen boot-args aus README. Erster Boot 4–5 min Apple-Logo.
6. Debug: OrangeFox temporär booten → `tools/sweet-log-pull.sh logs/boot.txt`; Crashes mit `tools/sweet-crash.py`.

## Realistische Erwartung
Bestenfalls Home-Screen ohne WLAN/BT/Audio/Kamera/GPU (CPU-Rendering ~20–30 fps). Bastel-/Lernprojekt.
Rechtlich grau (Apple-EULA); iOS-Dateien nicht ins Repo committen.
