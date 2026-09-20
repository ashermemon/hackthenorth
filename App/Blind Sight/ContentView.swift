//
//  ContentView.swift
//  Blind Sight
//
//  Created by Flora Yan on 2026-09-19.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var arSession = ARSessionManager.shared
    @StateObject private var belt = BeltController.shared
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var voiceController = VoiceQueryController()
    // EXPERIMENTAL — see VolumeButtonWatcher.swift for why AVCaptureEventInteraction wasn't
    // enough and what this trades away (toggle not hold, fragile HUD-reset trick). Not
    // ObservableObject — it just drives the same `recorder` everything else already observes,
    // so it's created once (lazily, in onAppear) and held here without needing @StateObject.
    @State private var volumeWatcher: VolumeButtonWatcher?

    #if DEBUG
    @State private var lastRecordingURL: URL?
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
            Text("Volume Down toggles recording, Volume Up repeats the last response (experimental)")
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
            #endif

            BeltDebugView(belt: belt)
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
                },
                onVolumeUp: { voiceController.replayLastResponse() }
            )
        )
        .environmentObject(arSession)
        .onAppear {
            arSession.start()
            belt.start()
            if volumeWatcher == nil {
                let watcher = VolumeButtonWatcher(recorder: recorder)
                watcher.onStop = { url in
                    #if DEBUG
                    lastRecordingURL = url
                    #endif
                    voiceController.handleRecordingFinished(url: url)
                }
                watcher.onVolumeUp = { voiceController.replayLastResponse() }
                volumeWatcher = watcher
            }
        }
        .onDisappear {
            belt.stop()
            arSession.stop()
        }
    }
}

#Preview {
    ContentView()
}
