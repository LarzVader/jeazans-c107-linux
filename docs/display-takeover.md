# Taking over the display pipeline from the vendor bootloader

Mainline Linux 7.2 has no driver for the A523 display pipeline (DE33 mixer,
TCON-LCD, DSI host, combo D-PHY). Projects that tried to bring the pipeline up
from scratch had a hard time: the Trimui Smart Pro S work had the panel lit but
no frame coming out of the display engine for a long time, and the panel
controller there overheated within minutes when the DSI clock was off.

On this tablet the vendor U-Boot already does all of that work: it powers the
panel, programs the PHY, the DSI host and the TCON, and leaves one UI layer of
the mixer scanning out its boot logo. `simpledrm` can show a picture by copying
into that buffer with the CPU, but that is slow, it has no vblank and no
brightness control, and Mesa falls back to software paths.

## The idea

Leave everything that is hard and dangerous alone and only touch what can
change while the pipeline keeps running:

1. **Scanout address.** The active UI layer is channel 6 at 0x51c1000. Writing
   a new address to its `ADDR` register (offset 0x10) switches the picture
   immediately, with no RCQ and no commit. That was proven at the U-Boot prompt
   with `mw.l 0x51c1010 0x60000000`, which flipped the screen to whatever was
   in that memory. This gives real page flips on CMA buffers.
2. **Frame interrupt.** The TCON-LCD1 raises TRI_FINISH once per frame
   (`GINT0`, enable bit 27, flag bit 11). That becomes vblank. Measured: one
   interrupt every 16 719 µs, 59.81 Hz, which is exactly 68 MHz / 860 / 1322.
3. **Backlight.** PWM0 channel 0 drives the brightness; its period register
   holds the entire cycle in the upper half and the active cycle in the lower
   half. Writing it changes the brightness at once. Together with the enable
   GPIO (PH18) this is a complete backlight device.

Nothing else is written: no TCON timing, no DSI register, no PHY, no clock
rate, no panel command. The DSI clock stays at the vendor value, so the
overheating problem of a self-programmed pipeline does not arise.

## The driver

`drivers/gpu/drm/sun4i/sun55i_takeover.c` (patch 0013), about 650 lines:

- One primary plane (XRGB8888 and ARGB8888, linear, no scaling), one CRTC with
  a fixed 800×1280 mode, a DSI encoder and a DSI connector.
- `drm_driver.name` is `"sun4i-drm"` on purpose: Mesa then uses `kmsro` and
  renders with Panfrost straight into the buffers allocated here.
- The plane update stores address, pitch and format; the frame interrupt
  applies them right after a frame went out, so the new buffer is visible from
  the next frame and the old one is no longer read when user space hears of
  the flip. Disabling the plane clears the layer enable bit immediately so the
  mixer never reads freed memory.
- Before taking over, the driver checks that the interrupt really fires
  (`check_only=1` does only that and leaves the display alone). Only then it
  removes `simpledrm` and registers itself. Clocks and power domains of the
  pipeline are taken before `simpledrm` lets go of them, otherwise they would
  be switched off under the running panel.
- The backlight device `panel` has 100 steps; 0 is dark (the emergency stop
  relies on that), 1–4 are clamped to the 5 % minimum the vendor uses.
- On removal the layer is pointed back at the reserved boot framebuffer.

The device tree node lists only the three register windows it touches (layer,
TCON, PWM channel) plus the same clocks and power domains as the
`simple-framebuffer` node, so both can coexist during early boot.

The driver is loaded through `modules-load.d` before the desktop starts. KWin
does not move from `simpledrm` to a new device at runtime: stopping
`plasma-mobile.service` leaves `plasma-kwin_wayland.service` running without
its logind session.

## Limits

- The panel cannot be initialised or powered down by Linux. If the vendor
  bootloader does not light the panel, there is no picture.
- The framebuffer address depends on the U-Boot heap. With the vendor boot
  logos present it is 0xb1f13000; without them it was 0xb1f0e000. The
  `fb_mem` reserved region and the layer address must match.
- The `fb_mem` region (4 MB) stays reserved although it is only used until the
  driver takes over.
- There is no suspend/resume.

## Testing safely

Because the panel controller cannot be monitored, a software emergency stop was
used during bring-up (`tools/display-notaus.py`): it turns every backlight to 0
and cuts the panel rail (AXP717 CLDO4, register 0x91 bit 3) over raw I2C when
the power key or volume-down is pressed, when a dead-man timer expires, or on
request from the PC. After it fires the picture only comes back after a reboot.
`tools/anzeige-test.sh` runs the staged test (interrupt check, console on the
new buffer, `kmscube`, brightness) with the emergency stop armed.
