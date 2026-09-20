# Belt UDP packet spec (v1)

Shared interface between the iPhone app (sender) and the ESP32 (receiver).
Change it only by agreeing on both sides.

## Transport

| | |
|---|---|
| Protocol | UDP, phone → ESP32, one-way (no reply) |
| ESP32 network | ESP32 joins the phone's Personal Hotspot as a client |
| ESP32 IP | `172.20.10.13`, fixed (an iPhone hotspot is always `172.20.10.0/28`, phone at `.1`) |
| UDP port | `4210` |
| Send rate | ~5 Hz (a few times per second) |

The phone hosts the hotspot, so it keeps cellular for ElevenLabs / Gemini and the belt link
needs no separate WiFi network. Personal Hotspot must be on, with **Maximize Compatibility**
enabled (the ESP32 is 2.4 GHz only). The fixed address is set in
`firmware/belt_arduino/belt_config.h` and mirrored in `AppConfig.esp32Host`; keep the two in step.

## Payload: 6 bytes, binary

| Byte | Name | Value |
|---|---|---|
| 0 | magic | `0xB7` |
| 1 | seq | u8, increments per packet, wraps 255 → 0 |
| 2 | z0 | left hip (-70°), urgency 0–255 |
| 3 | z1 | left pocket (-20°), urgency 0–255 |
| 4 | z2 | right pocket (+20°), urgency 0–255 |
| 5 | z3 | right hip (+70°), urgency 0–255 |

**Each zone byte is urgency, not motor strength.** Closer obstacle = higher value, and the ESP32
turns it into a pulse pattern (`firmware/belt_arduino/belt_pulse.h`):

| Value | Motor |
|---|---|
| `0` | off |
| `1`–`254` | pulses, 1 → 6 per second, spaced geometrically (each pulse `BELT_PULSE_ON_MS`, only the gap changes) |
| `255` | solid buzz (obstacle at the near limit) |

Every pulse is driven at the same strength, so it always starts crisply at any rotor angle, with no
dead zone. With the app's default range (solid at 0.5 m or closer, silent at 2.0 m or beyond):
2.0 m ≈ 1 pulse/s, 1.6 m ≈ 1.6, 1.2 m ≈ 2.6, 0.9 m ≈ 3.7, 0.7 m ≈ 4.7, 0.55 m ≈ 5.6, then solid.

## Receiver rules (ESP32)

- Ignore any datagram that is not exactly 6 bytes or whose byte 0 is not `0xB7`.
- A packet is applied only if its `seq` is newer than the last applied one, compared with
  wraparound: `(int8_t)(seq - last) > 0` (a plain `>` breaks at 255 → 0). This drops reordered or
  duplicate packets; it does not retry lost ones, since the next update supersedes them.
  **Exception:** if nothing has been applied for `HOLD_MS`, the belt is already silent, so the
  next valid packet is accepted whatever its `seq`. Without this, restarting the phone app
  (`seq` back at 0) would leave the belt ignoring packets for up to 128 updates.
  Implemented and unit-tested in `firmware/belt_arduino/belt_protocol.h`.
- Every valid packet replaces the whole 4-zone urgency state. The pulse timing runs on the ESP32,
  not the phone: the phone sends only ~5 updates a second, too slow to make a 6 per second beat.
- No valid packet for `HOLD_MS` (default 500 ms) → all motors off.

## Open items (tune by feel on the real belt)

All in `firmware/belt_arduino/belt_config.h`, none verified on hardware yet:

- `BELT_PULSE_DUTY` (motor strength during a pulse, currently 200) and `BELT_MAX_DUTY` (safety cap).
- `BELT_PULSE_ON_MS` (90), `BELT_PULSE_MIN_HZ` (1) and `BELT_PULSE_MAX_HZ` (6). Above about 6–7 per
  second a motor's spin-up and spin-down blur the pulses into a continuous buzz.
- `BELT_PWM_FREQ_HZ` (10 kHz), the motor-drive carrier, separate from the pulse rate.
