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

    #if DEBUG
    @StateObject private var debugRecorder = AudioRecorder()
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
            // TODO(voice): AVCaptureEventInteraction / .onCameraCaptureEvent replaces this
            // debug button — it only fires while this view's ARSession (below) is running.

            #if DEBUG
            // TEMPORARY: stand-in for the volume-down push-to-talk trigger, just to verify
            // AudioRecorder produces a valid file. Remove once AVCaptureEventInteraction is wired.
            Button(debugRecorder.isRecording ? "Stop Recording" : "Start Recording") {
                if debugRecorder.isRecording {
                    lastRecordingURL = debugRecorder.stop()
                } else {
                    debugRecorder.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(debugRecorder.isRecording ? .red : .accentColor)

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
        .environmentObject(arSession)
        .onAppear { arSession.start() }
        .onDisappear { arSession.stop() }
    }
}

#Preview {
    ContentView()
}
