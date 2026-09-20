//
//  ContentView.swift
//  Blind Sight
//
//  Created by Flora Yan on 2026-09-19.
//

import AVFoundation
import SwiftUI

struct ContentView: View {
    @StateObject private var arSession = ARSessionManager.shared
    @StateObject private var recorder = AudioRecorder()

    #if DEBUG
    @State private var lastRecordingURL: URL?
    // Retained so it isn't deallocated mid-playback — AVAudioPlayer doesn't keep itself alive.
    @State private var debugPlayer: AVAudioPlayer?
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
                        }
                )

            #if DEBUG
            if let lastRecordingURL {
                Text("Saved: \(lastRecordingURL.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Sandboxed tmp/ isn't reachable from the Files app or Finder on a real
                // device, so play it back in-app instead of hunting for the file.
                Button("Play Recording") {
                    do {
                        debugPlayer = try AVAudioPlayer(contentsOf: lastRecordingURL)
                        debugPlayer?.play()
                    } catch {
                        print("AudioRecorder debug: playback failed — \(error)")
                    }
                }
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
                }
            )
        )
        .environmentObject(arSession)
        .onAppear { arSession.start() }
        .onDisappear { arSession.stop() }
    }
}

#Preview {
    ContentView()
}
