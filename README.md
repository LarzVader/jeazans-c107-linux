# Linux on the Jeazans C107 tablet (Allwinner A523)

postmarketOS with a near-mainline Linux 7.2 kernel on a cheap Android 14 tablet
built around the Allwinner A523 (sun55i). Wi-Fi, display, GPU, touch, sound,
battery, buttons and auto-rotation work; Plasma Mobile runs GPU-accelerated.

This is a hobby bring-up project, tested on exactly one device. It is published
so that other people with A523 hardware can reuse the findings, the patches and
the tools. It is **not** a turnkey installer.

> **Warning.** Everything here is experimental. Installing it unlocks the
> bootloader, wipes the Android user data and rewrites partitions. A mistake
> can leave the tablet unable to boot. Keep a full eMMC backup before you touch
> anything, and know how to get back (see *Rollback*). No support is offered.

## Status

| Component | State | Notes |
|---|---|---|
| Boot | works | Vendor U-Boot (2018.07) stays, our Android boot image lives in slot B, U-Boot environment of slot B starts it automatically |
| Root filesystem | works | postmarketOS image written into the former `userdata` partition (eMMC), seen as loop subpartitions |
| Serial console | works | UART0 on the microSD pins (PF2/PF4) through a microSD sniffer and a USB-UART |
| Wi-Fi | works | AIC8800D80 on SDIO, AICSemi's RFC v3 driver plus six patches of ours (0005–0009, 0011), stable MAC address |
| Display | works | 800×1280 MIPI-DSI panel, 59.81 Hz. Linux takes over the pipeline that the vendor U-Boot leaves running: page flips, vblank, backlight (patch 0013, see `docs/display-takeover.md`) |
| GPU | works | Mali-G57 with Panfrost, KWin/Plasma Mobile use it |
| Touch | works | Silead GSL3676, firmware from the Android image, retry on warm boot (patch 0010) |
| Sound | works | Internal A523 codec: speakers, headphones, jack detection and automatic switching. Microphones untested |
| Battery, charger | works | AXP717: capacity, voltage, charge control, USB input. A small service keeps the battery near 50 % for 24/7 operation on the charger |
| Power key, volume keys | works | AXP717 PEK and the LRADC |
| Accelerometer | works | SC7A20 on I2C1, KWin rotates the screen |
| USB gadget network | works | RNDIS (NCM stalled under load) |
| Bluetooth | missing | AIC8800, needs the Bluetooth part of the driver |
| Cameras | missing | |
| Suspend | disabled | not tested on this kernel, the device is used as a server |
| CPU frequency scaling, thermal | missing | A523 cpufreq is still in flight upstream |
| Display init by Linux | missing | the panel is only brought up by the vendor U-Boot (see limitations) |

## Hardware

| | |
|---|---|
| SoC | Allwinner A523 (sun55i), octa-core Cortex-A55, Mali-G57 MC1 |
| RAM, storage | 4 GB, 128 GB eMMC |
| Display | 800×1280 MIPI-DSI, 4 lanes, JD9365DA-class controller ("JD9365DA_QC" in the vendor tree), 68 MHz pixel clock |
| Touch | Silead GSL3676 on I2C0 (0x40), IRQ PH9, wake PH10, rail CLDO2 |
| Wi-Fi/Bluetooth | AIC8800D80 on SDIO (MMC1), power enable PL7, WL_REG_ON PM1 |
| PMICs | AXP717 (AXP2202) at 0x34 and AXP313A (AXP1530) at 0x36 on R_I2C0 |
| Battery | 4990 mAh (vendor device tree) |
| Sensors | Silan SC7A20 accelerometer on I2C1 (0x19) |
| Audio | A523 internal codec, speaker amplifier enable PH6, headphone jack with detection |
| Shipped software | BigdroidOS / Android 14, build `863C_V2.8_SQ9365QC_C107_EEA` |

Details, register values and pin assignments are in `docs/hardware.md`.

## How it boots

1. The BROM loads the vendor bootloader from the eMMC (or from a microSD card
   first, which is the rescue path: `u-boot/` contains a self-signed TOC0 SPL
   for that).
2. The vendor U-Boot (slot B, `bootloader_b`) reads its environment from
   `env_b`. That environment was rewritten so that it runs our boot command
   after a short window for Ctrl-C on the serial console.
3. `boot_b` holds an Android boot image built by `tools/baue-bootimg.py`:
   the uncompressed kernel `Image`, the postmarketOS initramfs and our device
   tree. The vendor `bootm` only accepts uncompressed kernels; our boot image
   carries the device tree itself, so `vendor_boot` and `dtbo` of slot B are
   not needed for this path.
4. The postmarketOS initramfs finds the root filesystem in the former
   `userdata` partition and switches to it.

Android stays in slot A and can be restored by putting back the saved `misc`
partition (and, if touched, the slot A images).

## Repository layout

```
pmaports/device/testing/
  linux-jeazans-c107/      kernel package: config, device tree, patches 0001-0016
  device-jeazans-c107/     device package: deviceinfo, services, module loading, ALSA UCM profile
  firmware-jeazans-c107-*/ package recipes for the Wi-Fi and touch firmware (blobs not included)
tools/                     scripts used on the PC and on the tablet (comments in German)
u-boot/                    mainline U-Boot work: patches, defconfigs, device tree, FEL and rescue scripts
docs/                      hardware notes, the display takeover write-up, register dumps
LICENSES/                  license texts
```

The pmaports directories drop into a postmarketOS `pmaports` checkout under
`device/testing/`. The kernel is `linux-postmarketos-stable` 7.2.11 with the
configuration trimmed to the Allwinner platform (the vendor `bootm` needs the
kernel plus initramfs to fit into the 64 MiB `boot_b`).

## Kernel patches

| Patch | Origin | What it does |
|---|---|---|
| 0001–0004 | AICSemi, RFC v3 for wireless-next | AIC8800 Wi-Fi driver |
| 0005 | this project | build the AIC driver on 7.2 |
| 0006 | this project | accept the AIC8800D80 revision 7 found in this tablet |
| 0007 | this project | load the BSP firmware without a device (devres on SDIO function 1 gave -EBUSY) |
| 0008 | this project | do not oops on a scan confirmation after an abort |
| 0009 | this project | keep `change_station` in station mode, otherwise the 802.1X port stays closed |
| 0010 | this project | Silead: retry the setup if the status check fails after a warm reboot |
| 0011 | this project | AIC: allow setting the MAC address (no MAC in the eFuse) |
| 0012 | this project, local only | simpledrm: report the connector as DSI so that KWin treats it as internal |
| 0013 | this project | `sun55i_takeover`: DRM driver that takes over the running display pipeline |
| 0014–0016 | Juan Manuel López Carrillo, [orangepi-4a-mainline](https://github.com/ut-slayer/orangepi-4a-mainline) | A523 internal codec driver, a faithful port of the vendor driver |

Candidates for upstream: 0006–0009 and 0011 (replies to the AICSemi RFC
thread), 0010, the LRADC node and the AXP717 quirks noted in
`docs/hardware.md`. Patch 0013 is tied to what this vendor bootloader leaves
behind and is not upstream material; Chen-Yu Tsai is working on a proper A523
codec in `sun4i-codec`, patches 0014–0016 should be replaced by it once it
lands.

## Building and installing

There is no single installer. This is the path that was taken, in order; the
scripts in `tools/` are the ones used, see their header comments.

1. **Backup.** Unlock the bootloader (`fastboot flashing unlock`, this wipes
   the Android user data), then save the whole eMMC. Two ways were used: a
   rooted Android (DSU/GSI) with `dd`, and mainline U-Boot started over FEL
   exporting the eMMC read-only over USB (`u-boot/starte-fel.sh sichern`,
   `u-boot/sichere-emmc.sh`, U-Boot patch 0001).
2. **Firmware.** Copy `/vendor/etc/firmware/aic8800d80/*` and
   `/vendor/etc/firmware/gsl_firmware/*` from the Android image into the two
   `firmware-jeazans-c107-*` package directories (file names as in their
   `APKBUILD`). The blobs are not redistributed here.
3. **Packages.** Put the `pmaports/device/testing/*jeazans*` directories into
   your pmaports checkout, then `pmbootstrap build linux-jeazans-c107
   device-jeazans-c107 firmware-jeazans-c107-aic8800
   firmware-jeazans-c107-gslx680` (`tools/baue-kernel.sh` keeps sudo awake
   for the 25-minute kernel build).
4. **Root filesystem.** `pmbootstrap install` creates the image
   (`tools/baue-abbild.sh`); it is written raw into the former `userdata`
   partition. Note that `.gitignore` excludes `*.bin` and `*.img`, so the
   firmware blobs and images you add stay out of git.
5. **Boot image and device tree.** `tools/baue-dtb.sh` builds the device tree
   with the memory node and the reserved regions the vendor U-Boot expects,
   `tools/liefere-boot-abbild.sh` builds the boot image from the kernel package
   and the initramfs of the running tablet, and `tools/aktualisiere-kernel.sh`
   (on the tablet) installs packages and writes `boot_b`. The first time,
   `boot_b` is written with fastboot.
6. **U-Boot environment.** `tools/baue-env.py` produces the `env_b` image
   that boots Linux automatically; the vendor U-Boot has no shell scripting
   (no Hush), only plain command lists.
7. **Rollback.** `tools/stelle-android-wieder-her.sh` restores slot A from
   the backup. The microSD rescue card (`tools/baue-notfall-sd.sh`,
   `u-boot/jeazans_c107_rettung_defconfig`) boots even when the eMMC
   bootloader is damaged, because the BROM tries the card first.

The kernel command line needs `clk_ignore_unused`: without it Linux gates
clocks that the firmware's PSCI reset depends on, and a reboot waits for the
watchdog.

## Limitations and known issues

- The display is only initialised by the vendor U-Boot. The kernel driver keeps
  the pipeline running and changes the scanout address, the frame interrupt and
  the backlight duty cycle. The panel cannot be powered down and brought back
  by Linux; a different bootloader build (or different boot logos) can move the
  framebuffer address, which must then be updated in the device tree.
- The codec driver reports wrong dB ranges for two controls; the ALSA UCM
  profile therefore lets PulseAudio control the volume in software.
- The AXP717 battery driver reports `current_now` with a constant offset
  (~414 mA with no current flowing), so UPower's power and time estimates are
  wrong. `voltage_min` and the runtime charge-current limit are also off.
- Bluetooth, cameras, suspend, CPU frequency scaling and thermal management are
  not done. The microphones have not been tested.
- The kernel runs with `lockdown=integrity`; `/dev/mem` is unavailable, so
  register pokes need the U-Boot prompt or a kernel without lockdown.

## Credits

- AICSemi (Yanli Yang) for the AIC8800 driver RFC that patches 0001–0004 are
  taken from.
- Juan Manuel López Carrillo / AurealNix for the A523 codec driver
  ([orangepi-4a-mainline](https://github.com/ut-slayer/orangepi-4a-mainline)).
- Midgy Balon's [Trimui Smart Pro S](https://github.com/MidG971/trimui_smart_pro_s)
  notes on the A523 display, PWM and codec, which pointed at several fixes.
- Chen-Yu Tsai, Andre Przywara and the linux-sunxi community for the A523
  mainline work this builds on.
- postmarketOS.

The breakthroughs in this bring-up were achieved together with an AI
assistant. The maintainer drove the work, reviewed the results and tested
everything on the real device.

## License

Kernel patches, the kernel configuration and the device trees are GPL-2.0-only
(the device trees are additionally offered under MIT, as marked in the files);
the U-Boot patches are GPL-2.0-or-later like U-Boot itself. Patches by other authors keep their own copyright
notices. The scripts in `tools/` and `u-boot/` and the documentation in `docs/`
are MIT. See `LICENSES/`. No firmware is included.
