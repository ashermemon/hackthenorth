# BlindSight

Assistive navigation belt + iPhone app for blind/low-vision users. Hack the North 2026.
Full spec: see the PRD.

## Project layout

- `App/Blind Sight/Core/` — shared code. Don't fork these; extend them.
  - `ARSessionManager` — the one ARKit session for the app (LiDAR depth + RGB + pose).
    Belt reads depth off it, Voice grabs RGB frames off it. It's also the active capture
    session `AVCaptureEventInteraction` needs running to fire. Delegate callbacks hop to
    main explicitly before touching `@Published` state — keep that pattern if you touch it.
  - `AppConfig` — ESP32 host/port, belt update rate, Gemini model id, the Gemini system prompt.
  - `Models` — `BeltZone` / `BeltCommand`, the belt↔ESP32 packet contract (in-memory shape).
  - `BeltProtocol` — the actual 6-byte UDP wire format, see below.
  - `FrameProviding` / `MockFrameProvider` — lets Voice code depend on "give me a JPEG" instead
    of `ARSessionManager` directly, so it can be built/tested in Simulator (see "Testing
    without hardware" below).
  - `Secrets` — API keys, gitignored. Copy `Secrets.example.swift` → `Secrets.swift` and fill in.
- `App/Blind Sight/Belt/` — sensing & belt control loop (depth → zone/intensity → ESP32 UDP).
- `App/Blind Sight/Voice/` — voice query pipeline (button → STT → Gemini → TTS).
- `tools/belt_packet_listener.py` — standalone UDP listener that decodes belt packets, for
  verifying the phone sends correctly before ESP32 firmware exists.

Xcode syncs `Blind Sight/` automatically (file-system-synchronized group) — add `.swift`
files under `Belt/` or `Voice/` and they're picked up in the build with no `.pbxproj` edit.
Stay in your own folder + `Core/`; if you need to change an existing shared type in `Core/`,
flag it to the other person first since both features depend on it.

## Belt wire protocol

Phone → ESP32, UDP, `AppConfig.esp32Host:esp32Port` (default port 4210). 6 bytes, fixed size,
no endianness concerns (every field is a single byte). This is the one interface Xcode's
type checker can't verify for you, since the ESP32 firmware is a separate codebase/language —
whoever implements the firmware decoder should match this exactly, not re-derive it:

| Byte(s) | Field  | Meaning |
|---|---|---|
| 0 | magic | Always `0xB7`. Firmware should ignore any packet where this doesn't match. |
| 1 | seq | Wraps 0–255, increments per packet. Only apply a packet if it's newer than the last applied one: `(int8_t)(seq - lastAppliedSeq) > 0` — plain `>` breaks on wraparound. This guards against *reordering*, not drops; per the PRD a dropped packet is just superseded by the next update, never retried. |
| 2–5 | z0..z3 | PWM duty cycle 0–255, in order leftHip, leftPocket, rightPocket, rightHip. |

Firmware should also hold its last commanded state briefly rather than zeroing all motors on
a single missed packet (PRD risk mitigation) — that's a timeout/watchdog on the decode side,
separate from the seq check above.

## Testing without hardware

- **Voice**: construct `VoiceQueryController(frameProvider: MockFrameProvider())` to run the
  whole STT → Gemini → TTS chain in Simulator without any camera. A hardcoded transcript
  string in place of real STT output works too, for testing just the Gemini/TTS half.
- **Belt**: run `python3 tools/belt_packet_listener.py` on a machine on the same WiFi as the
  phone (point `AppConfig.esp32Host` at that machine's IP) to confirm packets are framed
  correctly before any ESP32 is flashed.

## Known gap — verify on real hardware before branching further

Everything above type-checks against the iOS Simulator SDK, but ARKit's `sceneDepth` (LiDAR)
never runs in Simulator at all — so that hasn't actually confirmed the belt loop's core
dependency works. **Before building much more on this foundation, build and run the app on
a real LiDAR iPhone** (Pro model) and confirm `ARSessionManager` starts, `isRunning` flips
true, and depth frames actually arrive. Use a matching-or-newer Xcode than what generated
this project — an older local Xcode failed to even open the `.xcodeproj` (format 110) when
this groundwork was built, so that mismatch is worth ruling out too.

## Git workflow

- `feature/belt-sensing` and `feature/voice-query`, branched off `basic-app-config` /
  `main` after groundwork — one per person, stay in your own folder + `Core/` per above.
- Push small commits often; PR into `main` every 30–60 min rather than sitting on a big diff.

## Setup

```
cp "App/Blind Sight/Core/Secrets.example.swift" "App/Blind Sight/Core/Secrets.swift"
# fill in elevenLabsAPIKey / geminiAPIKey in Secrets.swift
```

Then open `App/Blind Sight.xcodeproj` in Xcode. Requires a LiDAR-equipped iPhone (Pro model)
for on-device testing — ARKit scene depth doesn't run in the Simulator.
