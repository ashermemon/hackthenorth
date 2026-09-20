//
//  WearerModeView.swift
//  Blind Sight
//
//  Default screen: what the wearer actually uses. Everything here drives the same
//  recorder/voiceController the hardware triggers (CaptureEventTrigger, VolumeButtonWatcher) use,
//  set up once in ContentView — this on-screen button is just one more entry point into them.
//

import SwiftUI

struct WearerModeView: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var voiceController: VoiceQueryController
    // Observed separately from `belt` — BeltController doesn't republish its sender's changes,
    // so this view needs its own subscription to see `isReady` updates (same pattern as BeltDebugView).
    @ObservedObject var sender: BeltUDPSender
    @Binding var mode: AppMode

    init(recorder: AudioRecorder, voiceController: VoiceQueryController, belt: BeltController, mode: Binding<AppMode>) {
        self.recorder = recorder
        self.voiceController = voiceController
        self.sender = belt.sender
        self._mode = mode
    }

    private enum Stage: CaseIterable {
        case ready, listening, thinking, speaking

        var label: String {
            switch self {
            case .ready: return "Ready"
            case .listening: return "Listening"
            case .thinking: return "Thinking"
            case .speaking: return "Speaking"
            }
        }
    }

    private var stage: Stage {
        if recorder.isRecording { return .listening }
        if voiceController.isSpeaking { return .speaking }
        if voiceController.isProcessing { return .thinking }
        return .ready
    }

    private var subtitle: String {
        switch stage {
        case .ready: return "Hold the button to ask"
        case .listening: return "Release to send"
        case .thinking: return "Thinking about your question…"
        case .speaking: return "Speaking the answer…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            topBar

            VStack(alignment: .leading, spacing: 6) {
                Text(stage.label)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.bsTextSecondary)
            }

            stageIndicator

            micButton

            if let lastError = voiceController.lastError {
                Text("Last error: \(lastError)")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 6) {
                BSCaption(text: "Last answer")
                Text(voiceController.lastAnswerText ?? "No question asked yet.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .bsCard()

            Spacer(minLength: 0)

            Text("Volume Down also works as push to talk")
                .font(.system(size: 12))
                .foregroundStyle(Color.bsTextTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bsBackground.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(sender.isReady ? Color.bsAccent : Color.bsTextTertiary)
                    .frame(width: 8, height: 8)
                Text(sender.isReady ? "Belt linked" : "Belt offline")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                mode = .demo
            } label: {
                Text("Demo view")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.bsCard))
                    .overlay(Capsule().stroke(Color.bsCardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var stageIndicator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Stage.allCases, id: \.label) { candidate in
                    Capsule()
                        .fill(candidate == stage ? Color.bsAccent : Color.bsCard)
                        .frame(height: 4)
                }
            }
            HStack(spacing: 0) {
                ForEach(Stage.allCases, id: \.label) { candidate in
                    Text(candidate.label)
                        .font(.system(size: 11, weight: candidate == stage ? .semibold : .regular))
                        .foregroundStyle(candidate == stage ? .white : Color.bsTextTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var micButton: some View {
        VStack(spacing: 16) {
            Image(systemName: recorder.isRecording ? "mic.fill" : "mic")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.black)
            Text(recorder.isRecording ? "Release to send" : "Hold to ask")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.bsAccent)
        )
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in recorder.start() }
                .onEnded { _ in
                    let url = recorder.stop()
                    voiceController.handleRecordingFinished(url: url)
                }
        )
    }
}
