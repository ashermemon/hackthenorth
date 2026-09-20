# Belt UDP packet spec (v1)

Shared interface between the iPhone app (sender) and the ESP32 (receiver).
Change it only by agreeing on both sides.

## Transport

| | |
|---|---|
| Protocol | UDP, phone → ESP32, one-way (no reply) |
| ESP32 network | ESP32 hosts its own WiFi access point |
| ESP32 IP | `192.168.4.1` (ESP-IDF SoftAP default) |
| UDP port | `4210` |
| Send rate | ~5 Hz (a few times per second) |

The phone stays joined to the ESP32's AP for the belt link and uses cellular for
ElevenLabs / Gemini. The AP has no internet, so iOS will show "No Internet Connection".

## Payload: 6 bytes, binary

| Byte | Name | Value |
|---|---|---|
| 0 | magic | `0xB7` |
| 1 | seq | u8, increments per packet, wraps 255 → 0 |
| 2 | z0 | left hip (-70°), 0–255 |
| 3 | z1 | left pocket (-20°), 0–255 |
| 4 | z2 | right pocket (+20°), 0–255 |
| 5 | z3 | right hip (+70°), 0–255 |

Zone value: `0` = motor off, `255` = strongest. Closer obstacle = higher value.

## Receiver rules (ESP32)

- Ignore any datagram that is not exactly 6 bytes or whose byte 0 is not `0xB7`.
- A packet is applied only if its `seq` is newer than the last applied one, compared with
  wraparound: `(int8_t)(seq - last) > 0` (a plain `>` breaks at 255 → 0). This drops reordered or
  duplicate packets; it does not retry lost ones, since the next update supersedes them.
  **Exception:** if nothing has been applied for `HOLD_MS`, the belt is already silent, so the
  next valid packet is accepted whatever its `seq`. Without this, restarting the phone app
  (`seq` back at 0) would leave the belt ignoring packets for up to 128 updates.
  Implemented and unit-tested in `firmware/belt_fw/main/belt_protocol.c`.
- Every valid packet replaces the whole 4-zone state.
- No valid packet for `HOLD_MS` (default 500 ms) → all motors off.

## Open items (fill in after the PWM bench test)

- Minimum duty at which the motors actually vibrate (dead zone): **TBD**.
  Proposal: the phone maps distance → `[min_effective, 255]`, and the firmware stays
  dumb except for a safety cap on max duty.
- Max duty cap for motor protection: **TBD**.
