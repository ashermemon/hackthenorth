# PWM bench test

Answers the PRD's flagged risk: does PWM on the L298N **IN pins** (ENA/ENB jumpered on)
give smooth, independent intensity on all 4 channels? No WiFi, no phone. Do this before
the belt is assembled or the real firmware is written.

## Wiring

**ESP32 (DOIT DevKit V1) → L298N**

| Zone | ESP32 GPIO | L298N input | L298N output | Motor |
|---|---|---|---|---|
| 1 left hip | 33 | IN1 | OUT1 | OUT1 ↔ GND |
| 2 left pocket | 25 | IN2 | OUT2 | OUT2 ↔ GND |
| 3 right pocket | 26 | IN3 | OUT3 | OUT3 ↔ GND |
| 4 right hip | 27 | IN4 | OUT4 | OUT4 ↔ GND |

Each motor goes between one OUT terminal and the L298N's **GND** terminal (not between
OUT1 and OUT2). Motors can be wired either way round; they only ever spin one direction.

**Optional but recommended:** a 10 kΩ resistor from each IN pin to GND, so the motors stay
off while the ESP32 boots or resets (the pins float until the firmware configures them).

**Power (5 V USB power bank, no batteries needed)**

1. ESP32: micro-USB to the laptop for the bench test (that's also the serial console).
2. L298N: 5 V from the power bank (USB screw-terminal breakout, or a cut USB cable:
   red = 5 V, black = GND) to **both** the **VS** ("12V") terminal and the **5V** terminal.
3. **Remove the 5V-EN jumper** on the L298N (the small jumper by the power terminals). With
   only 5 V in, the onboard regulator can't work, and with the jumper on the 5V terminal is an
   output you'd be back-feeding.
4. **Leave the ENA and ENB jumpers ON.** (Different jumpers, easy to mix up.)
5. **Common ground:** ESP32 GND ↔ L298N GND ↔ power bank GND. Nothing works without this.

With 5 V in, the L298N drops about 2 V, so each motor sees roughly 3 V at 100% duty. That
should be fine for haptics. Some power banks switch off when the draw is very low; if the
L298N side keeps dying, turn on the bank's low-current / always-on mode.

The L298N pin labels vary between boards. Check the silkscreen on yours.

## Build and flash

One-time, in each new terminal:

```sh
. ~/esp/esp-idf/export.sh
```

Then:

```sh
cd firmware/bench_pwm
idf.py set-target esp32        # first time only
idf.py -p /dev/cu.usbserial-XXXX flash monitor
```

Find the port with `ls /dev/cu.*`. If none appears, try another cable (many are
charge-only) or install the CP2102/CH340 driver for your board. Exit the monitor with
`Ctrl+]`. Do **not** hold Enter; the keys act on a single press.

## Controls (single keypress in the monitor)

| Key | Action |
|---|---|
| `1`–`4` | select zone |
| `+` / `-` | duty ±10 on selected zone |
| `]` / `[` | duty ±1 |
| `0` / `z` | selected zone off / all off |
| `f` | cycle PWM frequency: 500 Hz, 1k, 2k, **5k (default)**, 10k, 20k |
| `a` | auto-ramp selected zone 0→255→0, prints every step (any key stops) |
| `t` | independence test (below) |
| `s` / `h` | status / help |

Duty is 0–255, the same scale as the UDP packet.

## Procedure

Run each step, hold a motor (or tape it to the belt fabric) so you can feel it.

1. **Ramp each zone** (`1`, `a` … `4`, `a`). Record the duty where it **first** buzzes going
   up, and where it **stops** going down. Motors usually need more to start than to keep
   running.
2. **Smoothness:** does strength change gradually across the ramp, or is it off/on with a
   threshold? Is there a jump after which it's just "full"?
3. **Independence test** (`t`). Phase 1: only the named zone should buzz. Phase 2: four
   distinct strengths should feel clearly different. Phase 3: an idle motor next to a busy
   one must not twitch.
4. **Frequency:** at one zone and ~50% duty, press `f` through all six and note which is
   quietest (whine) while still strongest to the touch.
5. **Stress:** on each zone (`1`–`4`) press `+` until duty is 255, so all four run at full
   for a minute. Watch for the ESP32 resetting (the monitor would show a boot banner) or the
   L298N/motors getting hot.

## Record here, then tell Everest

| Item | Result |
|---|---|
| Best PWM frequency | |
| Zone 1 / 2 / 3 / 4 start duty (going up) | |
| Zone 1 / 2 / 3 / 4 stop duty (going down) | |
| Independent + smooth on all 4? | |
| Any cross-talk / twitching? | |
| Audible whine at chosen frequency? | |
| ESP32 resets or motor overheating at full duty? | |

**Decision:** smooth and independent → keep 0–255 intensity. Not clean → fall back to
on/off (same packet, 0 or 255), per the PRD. The start-duty numbers also go into
`docs/PACKET_SPEC.md` (open items) so the phone's distance→intensity mapping can start at the
lowest duty that's actually felt.
