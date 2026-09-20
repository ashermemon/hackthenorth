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
  Implemented and unit-tested in `firmware/belt_arduino/belt_protocol.h`.
- Every valid packet replaces the whole 4-zone state.
- No valid packet for `HOLD_MS` (default 500 ms) → all motors off.

## Open items (measure on the real belt)

- Minimum duty at which the motors actually vibrate (dead zone): **TBD**. Find it with the
  app's debug screen: manual mode, raise one motor until it buzzes going up, and note where it
  stops going down. The phone maps distance → `[min_effective, 255]` (`BeltTuning.minFeltDuty`,
  currently a placeholder of 60), and the firmware stays dumb except for a safety cap on max duty.
- Max duty cap for motor protection (`BELT_MAX_DUTY`, currently 255): **TBD**.
