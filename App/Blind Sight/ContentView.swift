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

    @State private var mode: AppMode = .wearer
    @State private var showDebug = false

    #if DEBUG
    @State private var lastRecordingURL: URL?
    #endif

    var body: some View {
        Group {
            switch mode {
            case .wearer:
                WearerModeView(recorder: recorder, voiceController: voiceController, belt: belt, mode: $mode)
            case .demo:
                DemoModeView(belt: belt, recorder: recorder, voiceController: voiceController, mode: $mode)
            }
        }
        // Low-key access to the developer screen (tuning, manual overrides, host override, sweep
        // test) — not part of the wearer/demo UI, so it's an otherwise-invisible corner target
        // rather than a visible button.
        .overlay(alignment: .topTrailing) {
            Color.clear
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1.5) { showDebug = true }
        }
        // Primary trigger: on-screen press-and-hold (inside WearerModeView), not gated on iOS
        // version. Confirmed on-device that AVCaptureEventInteraction (wired below via
        // CaptureEventTrigger) does not reliably intercept Volume Down even with ARSession
        // confirmed running and no errors — ARKit's capture pipeline likely doesn't register as
        // "actively using the camera" the way a classic AVCaptureSession would, which is what
        // this API appears to actually require. Not depending on it working.
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
                onVolumeUp: { if !recorder.isRecording { voiceController.replayLastResponse() } }
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
                watcher.onVolumeUp = { [recorder] in if !recorder.isRecording { voiceController.replayLastResponse() } }
                volumeWatcher = watcher
            }
        }
        .onDisappear {
            belt.stop()
            arSession.stop()
        }
        .fullScreenCover(isPresented: $showDebug) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                    .padding(.top)
                }
                .environmentObject(arSession)
                .navigationTitle("Debug")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showDebug = false }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
