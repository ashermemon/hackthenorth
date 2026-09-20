# BlindSight

Assistive navigation belt + iPhone app for blind/low-vision users. Hack the North 2026.
Full spec: see the PRD.

## Project layout

- `App/Blind Sight/Core/` — shared code. Don't fork these; extend them.
  - `ARSessionManager` — the one ARKit session for the app (LiDAR depth + RGB + pose).
    Belt reads depth off it, Voice grabs RGB frames off it. It's also the active capture
    session `AVCaptureEventInteraction` needs running to fire.
  - `AppConfig` — ESP32 host/port, belt update rate, Gemini model id, the Gemini system prompt.
  - `Models` — `BeltZone` / `BeltCommand`, the belt↔ESP32 packet contract.
  - `Secrets` — API keys, gitignored. Copy `Secrets.example.swift` → `Secrets.swift` and fill in.
- `App/Blind Sight/Belt/` — sensing & belt control loop (depth → zone/intensity → ESP32 UDP).
- `App/Blind Sight/Voice/` — voice query pipeline (button → STT → Gemini → TTS).

Xcode syncs `Blind Sight/` automatically (file-system-synchronized group) — add `.swift`
files under `Belt/` or `Voice/` and they're picked up in the build with no `.pbxproj` edit.
Stay in your own folder + `Core/`; if you need to change an existing shared type in `Core/`,
flag it to the other person first since both features depend on it.

## Setup

```
cp "App/Blind Sight/Core/Secrets.example.swift" "App/Blind Sight/Core/Secrets.swift"
# fill in elevenLabsAPIKey / geminiAPIKey in Secrets.swift
```

Then open `App/Blind Sight.xcodeproj` in Xcode. Requires a LiDAR-equipped iPhone (Pro model)
for on-device testing — ARKit scene depth doesn't run in the Simulator.
