//
//  DemoModeView.swift
//  Blind Sight
//
//  Demo mode has two sub-screens: the belt ring (default) and the depth-view grid overlay,
//  reached via "Depth overlay" / "Belt ring". Both are for showing someone else what the belt is
//  sensing — not what the wearer uses day to day (see WearerModeView).
//

import SwiftUI

struct DemoModeView: View {
    @ObservedObject var belt: BeltController
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var voiceController: VoiceQueryController
    @ObservedObject var sender: BeltUDPSender
    @Binding var mode: AppMode

    @State private var showDepthView = false

    init(belt: BeltController, recorder: AudioRecorder, voiceController: VoiceQueryController, mode: Binding<AppMode>) {
        self.belt = belt
        self.recorder = recorder
        self.voiceController = voiceController
        self.sender = belt.sender
        self._mode = mode
    }

    var body: some View {
        if showDepthView {
            DepthGridOverlayView(belt: belt, sender: sender) {
                showDepthView = false
            }
        } else {
            ringScreen
        }
    }

    private var voiceLabel: String {
        if recorder.isRecording { return "Listening" }
        if voiceController.isSpeaking { return "Speaking" }
        if voiceController.isProcessing { return "Thinking" }
        return "Ready"
    }

    private func stepLabel(_ step: VoiceQueryController.PipelineStep) -> String {
        if step == .stt, voiceController.completedSteps.contains(.stt), let duration = voiceController.sttDuration {
            return String(format: "%.1f s", duration)
        }
        if voiceController.activeStep == step { return "running" }
        if step == .tts, voiceController.isSpeaking { return "speaking" }
        if voiceController.completedSteps.contains(step) { return "done" }
        return "waiting"
    }

    private var ringScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Demo mode")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    ModePill(mode: $mode)
                }

                HStack(spacing: 10) {
                    StatusChip(
                        label: "Belt link",
                        value: sender.isReady ? "Linked" : "Offline",
                        valueColor: sender.isReady ? .white : Color.bsTextSecondary,
                        dotColor: sender.isReady ? Color.bsAccent : Color.bsTextTertiary
                    )
                    StatusChip(label: "Packets", value: "\(Int(sender.packetsPerSecond)) / s")
                    StatusChip(label: "Voice", value: voiceLabel, valueColor: .bsAccent)
                }

                BeltRingChartView(urgencies: belt.urgencies)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                voicePipelineBox

                HStack(spacing: 12) {
                    BSButton(title: "Test belt", isProminent: true) { belt.runSweepTest() }
                    BSButton(title: "Depth overlay") { showDepthView = true }
                }

                if let question = voiceController.lastQuestionText, let answer = voiceController.lastAnswerText {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            BSCaption(text: "Asked")
                            Text(question).font(.system(size: 14)).foregroundStyle(.white)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            BSCaption(text: "Answer")
                            Text(answer).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .bsCard()
                }
            }
            .padding(20)
        }
        .background(Color.bsBackground.ignoresSafeArea())
    }

    private var voicePipelineBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            BSCaption(text: "Voice pipeline")
            HStack(spacing: 10) {
                pipelineCell(title: "STT", value: stepLabel(.stt), highlighted: voiceController.activeStep == .stt)
                pipelineCell(title: "Gemini", value: stepLabel(.gemini), highlighted: voiceController.activeStep == .gemini)
                pipelineCell(title: "TTS", value: stepLabel(.tts), highlighted: voiceController.activeStep == .tts)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bsCard()
    }

    private func pipelineCell(title: String, value: String, highlighted: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(highlighted ? Color.bsAccent : Color.bsTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.bsBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(highlighted ? Color.bsAccent : Color.bsCardBorder, lineWidth: highlighted ? 1.5 : 1)
        )
    }
}

#Preview {
    DemoModeView(belt: .shared, recorder: AudioRecorder(), voiceController: VoiceQueryController(), mode: .constant(.demo))
}
