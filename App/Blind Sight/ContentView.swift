//
//  ContentView.swift
//  Blind Sight
//
//  Created by Flora Yan on 2026-09-19.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var arSession = ARSessionManager.shared

    #if DEBUG
    @StateObject private var debugRecorder = AudioRecorder()
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
