//
//  ContentView.swift
//  Blind Sight
//
//  Created by Flora Yan on 2026-09-19.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var arSession = ARSessionManager.shared
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var voiceController = VoiceQueryController()
    // EXPERIMENTAL — see VolumeButtonWatcher.swift for why AVCaptureEventInteraction wasn't
    // enough and what this trades away (toggle not hold, fragile HUD-reset trick). Not
    // ObservableObject — it just drives the same `recorder` everything else already observes,
    // so it's created once (lazily, in onAppear) and held here without needing @StateObject.
    @State private var volumeWatcher: VolumeButtonWatcher?

    #if DEBUG
    @State private var lastRecordingURL: URL?
    @State private var debugStatus: String = ""
    #endif

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("BlindSight")
                .font(.title)
            Text(arSession.isRunning ? "Sensing active" : "Starting…")
                .foregroundStyle(.secondary)
            Text("Volume Down also toggles recording (experimental)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if voiceController.isProcessing {
                Text("Thinking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let lastError = voiceController.lastError {
                Text("Last error: \(lastError)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            // Primary trigger: on-screen press-and-hold, not gated on iOS version. Confirmed
            // on-device that AVCaptureEventInteraction (wired below via CaptureEventTrigger)
            // does not reliably intercept Volume Down even with ARSession confirmed running
            // and no errors — ARKit's capture pipeline likely doesn't register as "actively
            // using the camera" the way a classic AVCaptureSession would, which is what this
            // API appears to actually require. Not depending on it working.
            Text(recorder.isRecording ? "Release to Send" : "Hold to Ask")
                .font(.headline)
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(recorder.isRecording ? Color.red : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in recorder.start() }
                        .onEnded { _ in
                            let url = recorder.stop()
                            #if DEBUG
                            lastRecordingURL = url
                            #endif
                            voiceController.handleRecordingFinished(url: url)
                        }
                )

            #if DEBUG
            if let lastRecordingURL {
                Text("Saved: \(lastRecordingURL.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if voiceController.lastResponseAudio != nil {
                Button("Repeat Response") {
                    voiceController.replayLastResponse()
                }
            }

            // Per-stage isolation tests, per the task's "test each file before wiring the
            // full chain" instruction — each hits only one API, independent of the others.
            Divider()
            Text("Isolation tests").font(.caption).foregroundStyle(.secondary)

            Button("Test STT (last recording)") {
                guard let lastRecordingURL else {
                    debugStatus = "STT: no recording yet — use Hold to Ask first"
                    return
                }
                Task {
                    do {
                        let transcript = try await ElevenLabsSTT().transcribe(fileURL: lastRecordingURL)
                        debugStatus = "STT result: \(transcript ?? "(empty)")"
                    } catch {
                        debugStatus = "STT failed: \(error)"
                    }
                }
            }

            Button("Test Gemini (mock frame)") {
                Task {
                    do {
                        let answer = try await GeminiClient().answer(
                            question: "What am I looking at?",
                            frameProvider: MockFrameProvider()
                        )
                        debugStatus = "Gemini result: \(answer)"
                    } catch {
                        debugStatus = "Gemini failed: \(error)"
                    }
                }
            }

            Button("Test TTS (hardcoded string)") {
                Task {
                    do {
                        let audio = try await ElevenLabsTTS().synthesize(text: "This is a test of the text to speech pipeline.")
                        debugStatus = "TTS: got \(audio.count) bytes, playing…"
                        try await AudioPlayer().play(audio)
                        debugStatus = "TTS: playback finished"
                    } catch {
                        debugStatus = "TTS failed: \(error)"
                    }
                }
            }

            if !debugStatus.isEmpty {
                Text(debugStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            #endif
        }
        .padding()
        .background(
            CaptureEventTrigger(
                onPress: { recorder.start() },
                onRelease: {
                    let url = recorder.stop()
                    #if DEBUG
                    lastRecordingURL = url
                    #endif
                    voiceController.handleRecordingFinished(url: url)
                }
            )
        )
        .environmentObject(arSession)
        .onAppear {
            arSession.start()
            if volumeWatcher == nil {
                let watcher = VolumeButtonWatcher(recorder: recorder)
                watcher.onStop = { url in
                    #if DEBUG
                    lastRecordingURL = url
                    #endif
                    voiceController.handleRecordingFinished(url: url)
                }
                volumeWatcher = watcher
            }
        }
        .onDisappear { arSession.stop() }
    }
}

#Preview {
    ContentView()
}
