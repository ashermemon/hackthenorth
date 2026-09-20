# BlindSight

Assistive navigation belt + iPhone app for blind/low-vision users. Hack the North 2026.
Full spec: see the PRD.

## Project layout

- `App/Blind Sight/Core/` — shared code. Don't fork these; extend them.
  - `ARSessionManager` — the one ARKit session for the app (LiDAR depth + RGB + pose).
    Belt reads depth off it, Voice grabs RGB frames off it. Delegate callbacks hop to main
    explicitly before touching `@Published` state — keep that pattern if you touch it. (Not
    every capture API works alongside it: `AVCaptureEventInteraction` did not reliably fire
    for the volume buttons while this session runs, confirmed on a device — so on-screen
    "Hold to Ask" is the primary voice trigger; see `ContentView` and `Voice/`.)
  - `AppConfig` — ESP32 host/port, belt update rate, Gemini model id, the Gemini system prompt.
  - `Models` — `BeltZone` / `BeltCommand`, the belt↔ESP32 packet contract (in-memory shape).
  - `BeltProtocol` — the actual 6-byte UDP wire format, see below.
  - `FrameProviding` / `MockFrameProvider` — lets Voice code depend on "give me a JPEG" instead
    of `ARSessionManager` directly, so it can be built/tested in Simulator (see "Testing
    without hardware" below).
  - `Secrets` — API keys, gitignored. Copy `Secrets.example.swift` → `Secrets.swift` and fill in.
- `App/Blind Sight/Belt/` — sensing & belt control loop (depth → zone/intensity → ESP32 UDP),
  plus `BeltDebugView`, a developer screen with live zone bars, link status, tuning sliders
  and a manual/sweep mode for testing the belt with no depth.
- `App/Blind Sight/Voice/` — voice query pipeline (button → STT → Gemini → TTS).
- `App/BeltSelfTest/` — checks for the belt's depth → zone → intensity logic and the exact wire
  bytes, run on the Mac with `App/BeltSelfTest/run.sh` (no phone or Xcode project needed).
- `tools/belt_packet_listener.py` — standalone UDP listener that decodes belt packets, for
  verifying the phone sends correctly before ESP32 firmware exists.

Xcode syncs `Blind Sight/` automatically (file-system-synchronized group) — add `.swift`
files under `Belt/` or `Voice/` and they're picked up in the build with no `.pbxproj` edit.
Stay in your own folder + `Core/`; if you need to change an existing shared type in `Core/`,
flag it to the other person first since both features depend on it.

## Belt wire protocol

Phone → ESP32, UDP, `AppConfig.esp32Host:esp32Port` (default `172.20.10.13:4210`). The ESP32
joins the phone's **Personal Hotspot** as a client at that fixed address (an iPhone hotspot is
always `172.20.10.0/28`, phone at `.1`), so the phone keeps cellular for the voice APIs. Firmware:
`firmware/belt_arduino/` (Arduino-ESP32 core 3.x). 6 bytes, fixed size,
no endianness concerns (every field is a single byte). This is the one interface Xcode's
type checker can't verify for you, since the ESP32 firmware is a separate codebase/language —
whoever implements the firmware decoder should match this exactly, not re-derive it:

| Byte(s) | Field  | Meaning |
|---|---|---|
| 0 | magic | Always `0xB7`. Firmware should ignore any packet where this doesn't match. |
| 1 | seq | Wraps 0–255, increments per packet. Only apply a packet if it's newer than the last applied one: `(int8_t)(seq - lastAppliedSeq) > 0` — plain `>` breaks on wraparound. This guards against *reordering*, not drops; per the PRD a dropped packet is just superseded by the next update, never retried. **Exception:** if nothing has been applied for the hold window (500 ms), accept the next valid packet whatever its `seq` — the belt is already silent, and restarting the phone app resets `seq` to 0, which would otherwise be ignored for up to 128 updates. |
| 2–5 | z0..z3 | Urgency 0–255 per zone, in order leftHip, leftPocket, rightPocket, rightHip: 0 off, 1–254 pulses that come faster the closer the obstacle (1 → 6 per second), 255 solid. The ESP32 makes the pulses. |

Firmware should also hold its last commanded state briefly rather than zeroing all motors on
a single missed packet (PRD risk mitigation) — that's a timeout/watchdog on the decode side,
separate from the seq check above.

## Testing without hardware

- **Voice**: construct `VoiceQueryController(frameProvider: MockFrameProvider())` to run the
  whole STT → Gemini → TTS chain in Simulator without any camera. A hardcoded transcript
  string in place of real STT output works too, for testing just the Gemini/TTS half.
- **Belt logic**: `App/BeltSelfTest/run.sh` renders synthetic 3D scenes (walls, floor, boxes;
  portrait, landscape, level) through the ARKit camera model and checks zones, filtering,
  intensity and the packet bytes.
- **Belt packets**: run `python3 tools/belt_packet_listener.py` on a machine on the same WiFi as
  the phone and enter that machine's IP in the debug screen's host field (tap Apply). Note it
  needs a network where devices can reach each other; venue WiFi often blocks that.

## Verified so far

On a real iPhone 15 Pro (iOS 18.4):

- ARKit LiDAR depth arrives at 256×192, about 7–8 ms of belt processing per frame.
- Belt zones respond correctly to real obstacles (left/right, distance, closer = stronger),
  including chairs outdoors.
- The voice pipeline works end to end (question → STT → Gemini → TTS → spoken answer), and fast.

## Not verified yet

- **Phone → ESP32 delivery.** Packets are sent (the debug screen's counter rises) but have not
  yet been seen by a listener or the real belt.
- **Motors.** Nothing has been felt on real hardware in the pulse-rate design. The feel constants
  (`BELT_PULSE_DUTY`, pulse length, 1–6 per second, in `firmware/belt_arduino/belt_config.h`) are
  first guesses to tune on the real belt.

## Git workflow

- `feature/belt-sensing` and `feature/voice-query`, branched off `basic-app-config` /
  `main` after groundwork — one per person, stay in your own folder + `Core/` per above.
- Push small commits often; PR into `main` every 30–60 min rather than sitting on a big diff.

## Setup

```
cp "App/Blind Sight/Core/Secrets.example.swift" "App/Blind Sight/Core/Secrets.swift"
# fill in elevenLabsAPIKey / geminiAPIKey in Secrets.swift
```

Then open `App/Blind Sight.xcodeproj` in Xcode (use a version at least as new as the one that
generated the project — an older Xcode fails to open it). Requires a LiDAR-equipped iPhone
(Pro model), iOS 17.0+, for on-device testing — ARKit scene depth doesn't run in the Simulator.
Set your own signing team in Xcode, and don't commit that change (team ID / bundle ID).
