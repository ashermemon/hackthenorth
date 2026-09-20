# Belt firmware (Arduino)

The ESP32 is a motor driver: it joins the phone's Personal Hotspot, listens for the app's 6-byte
UDP packets ([docs/PACKET_SPEC.md](../../docs/PACKET_SPEC.md)), and drives four L298N inputs with
PWM. The phone decides *what is near*; this decides only *how to buzz it*.

- **How it buzzes:** each zone byte is **urgency**. `0` is off, `255` is a solid buzz, and `1`–`254`
  make that motor **pulse**, from 1 per second (far) up to 6 per second (close). Every pulse is the
  same length and the same strength; only the gap between pulses shrinks as things get closer. So a
  pulse always starts crisply, at any rotor angle, with no weak-signal dead zone.
- **Network:** joins your hotspot as a client at the fixed address `172.20.10.13`, UDP port `4210`.
- **Failsafe:** no valid packet for 500 ms → every motor off. That covers a missed packet (nothing
  changes for one), and a dead phone, app or link (the belt goes quiet by itself).
- **Order:** a packet is applied only if its `seq` is newer than the last one, except after the
  500 ms hold window, so restarting the app can't leave the belt ignoring packets.
- **Onboard LED:** fast blink = joining the hotspot; short flash every 2 s = joined, waiting for
  the phone; solid = packets arriving.

Settings are in [belt_config.h](belt_config.h). Your hotspot name and password go in `secrets.h`,
which is git-ignored.

## Wiring

**ESP32 (DOIT DevKit V1) → L298N**

| Packet byte | Position on the belt | ESP32 GPIO |
|---|---|---|
| z0 | far left (left hip) | 25 |
| z1 | inner left (left pocket) | 33 |
| z2 | inner right (right pocket) | 27 |
| z3 | far right (right hip) | 26 |

Left and right are the wearer's. **This is the belt as built:** its motors sit in a different order
from the original plan (which had GPIOs 33, 25, 26, 27 as far-left to far-right), so the table above
is not in pin order. It is set in `BELT_ZONE_GPIOS` in `belt_config.h`; if you rewire a motor, fix it
there and leave the app alone. GPIOs 33, 25, 26 and 27 go to the L298N inputs IN1 to IN4. Each motor
goes between one OUT terminal and the L298N's **GND** terminal (not between OUT1 and OUT2). Either
polarity works; they only spin one way.

**Optional but recommended:** a 10 kΩ resistor from each IN pin to GND, so the motors stay off
while the ESP32 boots or resets (the pins float until the firmware configures them).

**Power (5 V USB power bank, no batteries needed)**

1. ESP32: micro-USB to the power bank (or the laptop while flashing; that's also the serial console).
2. L298N: 5 V from the power bank (USB screw-terminal breakout, or a cut USB cable: red = 5 V,
   black = GND) to **both** the **VS** ("12V") terminal and the **5V** terminal.
3. **Remove the 5V-EN jumper** on the L298N (the small jumper by the power terminals). With only
   5 V in, the onboard regulator can't work, and with the jumper on the 5V terminal is an output
   you'd be back-feeding.
4. **Leave the ENA and ENB jumpers ON.** (Different jumpers, easy to mix up.)
5. **Common ground:** ESP32 GND ↔ L298N GND ↔ power bank GND. Nothing works without this.

With 5 V in, the L298N drops about 2 V, so each motor sees roughly 3 V at full duty, which is
plenty for haptics. Some power banks switch off when the draw is very low; if the L298N side keeps
dying, turn on the bank's low-current / always-on mode. L298N pin labels vary; check your board.

## Set up

1. **Hotspot:** on the iPhone, Settings → Personal Hotspot → on, and turn on **Maximize
   Compatibility** (the ESP32 only speaks 2.4 GHz and can't see a 5 GHz-only hotspot).
2. **Secrets:** copy `secrets.example.h` to `secrets.h` and fill in the hotspot name and password.
   Never commit `secrets.h`.
3. **Toolchain:** the Arduino-ESP32 core **3.x** (it uses the `ledcAttach(pin, freq, bits)` API,
   which doesn't exist in 2.x). Built and checked against 3.3.12, board "DOIT ESP32 DEVKIT V1".

   ```sh
   arduino-cli config add board_manager.additional_urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
   arduino-cli core update-index
   arduino-cli core install esp32:esp32@3.3.12
   ```

   (Or in the Arduino IDE: Boards Manager → "esp32 by Espressif Systems", version 3.x.)

## Build and flash

```sh
arduino-cli compile --fqbn esp32:esp32:esp32doit-devkit-v1 firmware/belt_arduino
arduino-cli upload  -p /dev/cu.usbserial-XXXX --fqbn esp32:esp32:esp32doit-devkit-v1 firmware/belt_arduino
arduino-cli monitor -p /dev/cu.usbserial-XXXX -c baudrate=115200
```

Find the port with `ls /dev/cu.*`. If none appears, try another cable (many are charge-only). The
monitor should print `Joined hotspot. Belt is at 172.20.10.13:4210`.

## Test without the app

Join a Mac to the same hotspot, then:

```sh
python3 tools/send_fake_zones.py sweep            # each zone ramps up and down in turn
python3 tools/send_fake_zones.py walk             # an obstacle approaching on the left
python3 tools/send_fake_zones.py walk --loss 0.3  # with 30% of packets dropped
python3 tools/send_fake_zones.py garbage          # malformed packets: motors must stay off
```

Check on the belt and the monitor: the LED goes solid while the script runs; the motors stop about
half a second after Ctrl+C; 30% loss doesn't make the pulses stutter; restarting the script mid-run
makes the belt respond again straight away. (`sweep` shows the pulses speeding up to solid on each
motor in turn.)

## Tune the feel

Everything is a constant at the top of [belt_config.h](belt_config.h), and none of it has been
verified on the real belt yet. Change one, re-flash, and feel it.

| Constant | Now | What it does |
|---|---|---|
| `BELT_PULSE_DUTY` | 200 | How hard the motor runs during a pulse (0–255). Lower it if it's too harsh, or if the motors overheat. |
| `BELT_PULSE_ON_MS` | 90 | Length of every pulse. |
| `BELT_PULSE_MIN_HZ` | 1 | Pulses per second for a far obstacle. |
| `BELT_PULSE_MAX_HZ` | 6 | Pulses per second just before solid. Above ~6–7 the motor's spin-up and spin-down blur pulses into a continuous buzz. |
| `BELT_PULSE_MIN_GAP_MS` | 60 | The rest between pulses never goes below this. |
| `BELT_PWM_FREQ_HZ` | 10000 | The motor-drive carrier (not the pulse rate). |
| `BELT_MAX_DUTY` | 255 | Hard safety cap on motor strength. |

To try it with no obstacle handy, open the app's debug screen, turn on **manual mode**, and drag a
zone's slider: at 0 the motor is off, then it pulses faster as you drag up, and 255 is solid. **Sweep test**
does that for each motor in turn. The distance-to-urgency range (solid at 0.5 m or closer, silent
at 2.0 m or beyond) is `BeltTuning` in the app, and the sliders on the debug screen change it live.

## Troubleshooting

- **LED keeps fast-blinking:** it isn't joining. Check the name and password in `secrets.h`, that
  Personal Hotspot is on with Maximize Compatibility, and that the phone is close.
- **Joined, but the app's packets don't arrive:** the app must send to `172.20.10.13` (its default).
  If your hotspot isn't an iPhone's, set `BELT_USE_STATIC_IP` to `0` in `belt_config.h`, read the
  address the monitor prints, and enter it in the app's debug screen (host field, then Apply).
- **Compile error about `ledcAttach`:** the core is too old; install 3.x.

## Tests

The packet parsing, the accept/reject rule and the pulse timing are plain C++, tested on the Mac
(the pulse tests simulate the clock a millisecond at a time):

```sh
firmware/belt_arduino/test_host/run.sh
```
