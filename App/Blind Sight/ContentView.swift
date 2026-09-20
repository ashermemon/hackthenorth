//
//  ContentView.swift
//  Blind Sight
//
//  Created by Flora Yan on 2026-09-19.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var arSession = ARSessionManager.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("BlindSight")
                .font(.title)
            Text(arSession.isRunning ? "Sensing active" : "Starting…")
                .foregroundStyle(.secondary)
            // TODO(voice): AVCaptureEventInteraction / .onCameraCaptureEvent attaches here —
            // it only fires while this view's ARSession (below) is actively running.
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
