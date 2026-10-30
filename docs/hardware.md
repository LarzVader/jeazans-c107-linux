# Hardware notes: Jeazans C107

Everything below was read from the device (vendor device tree, Android logs,
register dumps at the vendor U-Boot prompt) or measured under Linux. Dates
refer to October 2026.

## Boot chain and partitions

- BROM → vendor TOC0 bootloader on the eMMC. The BROM tries a microSD card
  first, so a card with a TOC0 image boots even when the eMMC is damaged.
- Vendor U-Boot 2018.07 (built March 2025), A/B slots. Commands available:
  `mw`, `md`, `setexpr`, `sleep`, `go`, `fdt`, `fastboot`, `sunxi_flash`,
  `bootm`, `disp`. No Hush shell, so the environment can only hold plain
  command lists. The environment is slot specific (`env_a`, `env_b`).
- DRAM starts at 0x40000000, U-Boot relocates to about 0xb5e8a000. Two
  regions must stay reserved for Linux: 0x48000000 (16 MiB, BL31/OP-TEE) and
  0xb6000000 (160 MiB).
- The vendor `bootm` accepts only uncompressed kernels and does not use
  `vendor_boot` or `dtbo` for our boot image; everything is in `boot_b`
  (64 MiB). Kernel, ramdisk and DTB offsets used: 0x10000000, 0x14000000,
  0x16000000.
- `boot_b` is `/dev/mmcblk0p6`. The root filesystem lives in the former
  `userdata` partition as a raw postmarketOS image (loop subpartitions).
- Rescue: a mainline U-Boot SPL signed as TOC0 with a self-generated key
  (`CONFIG_SPL_IMAGE_TYPE_SUNXI_TOC0=y`) boots from microSD; see
  `u-boot/jeazans_c107_rettung_defconfig`. Generate your own key.

### Serial console

UART0 on PF2/PF4, which are the microSD data pins. A microSD sniffer board
(SparkFun style) wired to a CP2102 (CD→TXD, CLK→RXD, GND) gives the console
at 115200 baud. The SD clock produces short bursts of garbage on the line, and
an unconnected CP2102 can replay stale data endlessly. `u-boot/uboot-sitzung.py`
catches the U-Boot greeting, sends Ctrl-C and runs commands at the prompt.

Reading the display engine channel registers at 0x5141000 (OVL channel 2)
hangs U-Boot; recovery is holding the power key for 6 s.

## Power management

Two PMICs on R_I2C0:

| Chip | Address | Role |
|---|---|---|
| AXP717 (AXP2202) | 0x34 | main rails, battery, charger, power key, ADC |
| AXP313A (AXP1530) | 0x36 | big CPU cores (DCDC1), DLDO1 for the Wi-Fi module |

Rails used by Linux (voltages from the vendor tree):

| Rail | Voltage | Consumer |
|---|---|---|
| DCDC2 | 920 mV | GPU and system parts |
| ALDO4 | 1.8 V | codec AVCC |
| BLDO1 | 1.8 V | Wi-Fi I/O (PG) |
| BLDO2 | 1.8 V | PM port |
| CLDO1 | 1.8 V | codec charge pump input, shared |
| CLDO2 | 3.3 V | touch controller |
| CLDO3 | 3.3 V | codec VDD, shared |
| CLDO4 | 3.3 V | panel (`lcd_power1`), the only consumer |
| DLDO1 (AXP313A) | 3.3 V | Wi-Fi module |

Battery: 4990 mAh, vendor charge voltage 4.35 V, charge current 768 mA,
termination 128 mA, input limit 2000 mA, temperature sensor active. The device
tree limits the charge voltage to 4.0 V and the `jeazans-c107-akku-halten`
service stops charging at about 3.9 V and resumes below 3.75 V, so the battery
rests near 3.85 V at about 50 % while the tablet runs on the charger.

AXP717 driver observations (7.2.11, candidates for fixes):

- `current_now` has a constant raw offset of about 414 (reads 413–416 with
  no current, 464 at ~50 mA, 1244 at full charge current). UPower's power and
  time estimates are therefore wrong.
- `voltage_min` uses a wrong mask and reads 2.6 V.
- The maximum charge current is read from register 0x33, so runtime writes to
  the limit fail.
- Writing `Not charging` / `Charging` to `status` works for stopping and
  resuming the charger.
- The ADC IIO device has no `name` attribute; find it through the device path
  (`…/axp717-adc/iio:device*`). The TS raw value is in half millivolts.

Power off works through PSCI (without a USB cable the tablet stays off; with a
cable the PMIC powers it back on). Reboot needs `clk_ignore_unused` on the
command line, otherwise the firmware's reset hangs until the watchdog (16 s)
fires. Holding the power key for about 6 s cuts power at the PMIC level.

## Display

- Panel: 800×1280, MIPI-DSI video mode, 4 lanes, pixel clock 68 MHz, timings
  from the vendor tree: ht 860 (hbp 40, hspw 20), vt 1322 (vbp 12, vspw 4),
  137×217 mm. Frame rate measured from the TCON interrupt: 59.81 Hz.
- Pipeline: DE mixer 0 → blender → TCON-LCD1 → DSI1 → combo PHY. The UI layer
  used by the vendor bootloader is channel 6 at 0x51c1000; its scanout
  address, pitch and format can be changed on the fly, without RCQ or a
  commit. RCQ is off.
- Framebuffer left by U-Boot: 0xb1f13000, 800×1280×4, ARGB8888 (with the
  vendor boot logos in place; without them it was 0xb1f0e000).
- Backlight: enable on PH18, brightness on PWM0 channel 0 (PD23), 50 kHz,
  period register 480 cycles, vendor default 20 %, minimum 5 %.
- Panel reset PD22, panel rail CLDO4.
- TCON-LCD1 interrupt is GIC SPI 92; TRI_FINISH (enable bit 27, flag bit 11,
  flags are cleared by writing 0) fires once per frame.
- Register dumps of the running pipeline (DE top, mixer, blender, TCON, DSI,
  PHY, CCU, PWM): `measurements/display-sollwerte-2026-10-30.txt` and
  `measurements/display-de-top-2026-10-30.txt`.

See `display-takeover.md` for the driver built on this.

## Touch

Silead GSL3676 on I2C0 (PH0/PH1), address 0x40, interrupt PH9, wake PH10,
supply CLDO2. Raw range 1664×896, axes swapped and mirrored in the device tree.
The firmware comes from the Android image (`gslX680_3676_1280x800_yhk.bin`,
vendor format: count, then register/value pairs, then tuning data; the kernel
driver wants only the pairs, the APKBUILD cuts them out). After a warm reboot
the controller often fails its status check; patch 0010 powers it off and
retries. All four corners are reached to within about 3 mm.

## Wi-Fi

AIC8800D80 (revision 7, firmware U02 v6.9.1.1) on SDIO (MMC1). Power enable
PL7 must be high, WL_REG_ON is PM1 behind DLDO1 of the AXP313A. The chip has no
MAC address in its eFuse; the firmware picks a random one at every boot, so the
driver was taught to set the MAC (patch 0011) and NetworkManager uses
`cloned-mac-address=stable`. The USB gadget network uses RNDIS because the
NCM function stalled in the transmit direction for up to two minutes under
load.

## Sound

A523 internal codec at 0x7110000, interrupt GIC SPI 190, DMA request 7 on the
MCU DMA controller, clocks and reset from the MCU CCU. Rails: ALDO4 (avcc),
CLDO3 (vdd), CLDO1 (cpvin). Speakers on LINEOUT L/R behind an amplifier
enabled by PH6 (active high); headphones on HPOUT; jack detection with
`jack-det-level 0`, threshold 8. Android used MIC1 (and MIC2) as the built-in
microphones and MIC3 for headsets; the Android mixer paths are the base of the
UCM profile in the device package.

Driver notes (patches 0014–0016): the TLV for `DAC Volume` ends at -1.16 dB
and the one for `LINEOUT Gain` maps 0–1 to 0 dB instead of mute, which makes
PulseAudio misbehave with hardware volume. Until that is fixed the UCM profile
sets no `PlaybackMixerElem`, so PulseAudio uses software volume. The vendor
driver enables RAMP bit 1 and VRP_LDO_EN at init; the Trimui project needed
those on its board as well.

## Buttons and sensors

- Power key: AXP717 PEK (`axp20x-pek`).
- Volume keys: LRADC at 0x2009800, interrupt GIC SPI 66, channel 0,
  646 mV (up) and 1080 mV (down), reference 1.8 V. The LRADC node is missing
  from the mainline `sun55i-a523.dtsi`.
- Accelerometer: SC7A20 on I2C1 (PH2/PH3, 400 kHz), address 0x19, mount
  matrix `-1 0 0 / 0 1 0 / 0 0 -1`. The panel is mounted portrait; landscape
  with the camera on the left is KWin's `Rotated270`.

## GPIO summary

| Pin | Use |
|---|---|
| PD22 | panel reset |
| PD23 | PWM0 channel 0, backlight brightness |
| PH0/PH1 | I2C0 (touch) |
| PH2/PH3 | I2C1 (accelerometer) |
| PH6 | speaker amplifier enable |
| PH9 | touch interrupt |
| PH10 | touch wake |
| PH18 | backlight enable |
| PF2/PF4 | UART0 (console on the microSD pins) |
| PL7 | Wi-Fi module power enable |
| PM1 | WL_REG_ON |

## Memory map of the display blocks

| Block | Address |
|---|---|
| DE top | 0x5008000 |
| Mixer 0 global | 0x5100000 |
| OVL channel 6 (active UI layer) | 0x51c1000 |
| Blender | 0x5281000 |
| TCON top | 0x5500000 |
| TCON-LCD1 | 0x5502000 |
| DSI1 | 0x5508000 |
| Combo PHY | 0x5509000 |
| CCU | 0x2001000 (DE at +0x600, display gates from +0xb00) |
| PWM0 | 0x2000c00 (channel 0 period at +0x104) |
