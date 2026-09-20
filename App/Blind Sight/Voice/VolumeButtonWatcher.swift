//
//  VolumeButtonWatcher.swift
//  Blind Sight
//
//  EXPERIMENTAL — legacy hardware-button hack, not the sanctioned trigger.
//
//  AVCaptureEventInteraction (CaptureEventTrigger.swift) is the correct, Apple-sanctioned way
//  to intercept hardware buttons, but confirmed on-device (iOS 18.7) that it doesn't fire
//  reliably with ARKit's session. This is the pre-iOS-17.2 community workaround: observe
//  AVAudioSession's outputVolume via KVO, treat a decrease as a "press," and snap the system
//  volume HUD back to baseline so it doesn't visibly drift and future presses keep registering.
//
//  Known limitations — read before depending on this:
//  - Toggle only, not a hold gesture. KVO gives "volume changed," not press/release phases,
//    so there's no way to distinguish button-down from button-up. This alternates
//    AudioRecorder.start()/stop() on each detected press, unlike the on-screen Hold to Ask
//    button, which does real press-and-hold.
//  - The HUD-reset relies on MPVolumeView's internal UISlider subview, which is not a
//    documented API and has broken across iOS versions before (Apple has tightened
//    MPVolumeView's internals repeatedly). If it stops working, delete this file — the
//    on-screen Hold to Ask button is the trigger everything else depends on, nothing else
//    breaks.
//  - There's a brief window before the reset fires where system volume actually changes,
//    which may be audible/visible — worth being deliberate about for an accessibility app.
//  - outputVolume reflects ANY volume change (Control Center, AirPlay, a connected
//    accessory), not specifically this device's hardware buttons, so false positives are
//    possible.
//

import AVFoundation
import MediaPlayer
import UIKit

final class VolumeButtonWatcher: NSObject {
    /// Fired after a detected press stops a recording, so callers can track the file the
    /// same way they do for the other trigger sources (on-screen button, CaptureEventTrigger).
    var onStop: ((URL?) -> Void)?

    private var kvoContext = 0
    private let session = AVAudioSession.sharedInstance()
    private var baselineVolume: Float = 0.5
    private let recorder: AudioRecorder

    private lazy var hiddenVolumeView: MPVolumeView = {
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.alpha = 0.001
        view.isUserInteractionEnabled = false
        return view
    }()

    init(recorder: AudioRecorder) {
        self.recorder = recorder
        super.init()
        activate()
    }

    private func activate() {
        do {
            try session.setCategory(.ambient, options: [])
            try session.setActive(true)
            baselineVolume = session.outputVolume
            session.addObserver(self, forKeyPath: "outputVolume", options: [.new], context: &kvoContext)
            attachHiddenVolumeView()
        } catch {
            print("VolumeButtonWatcher: failed to activate audio session — \(error)")
        }
    }

    private func attachHiddenVolumeView() {
        // Needs to be in a real window for its embedded slider to control system volume —
        // a detached MPVolumeView's slider won't reliably do anything. Best-effort: if the
        // key window isn't up yet, the HUD reset just won't do anything until it is.
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        else { return }

        if hiddenVolumeView.superview == nil {
            window.addSubview(hiddenVolumeView)
        }
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard context == &kvoContext, keyPath == "outputVolume" else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        guard let newVolume = change?[.newKey] as? Float else { return }

        if newVolume < baselineVolume {
            DispatchQueue.main.async { [weak self] in
                self?.togglePress()
            }
        }
        resetVolumeHUD()
    }

    private func togglePress() {
        if recorder.isRecording {
            let url = recorder.stop()
            onStop?(url)
        } else {
            recorder.start()
        }
    }

    private func resetVolumeHUD() {
        attachHiddenVolumeView()
        let target = baselineVolume
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let slider = self?.hiddenVolumeView.subviews.first(where: { $0 is UISlider }) as? UISlider else { return }
            slider.setValue(target, animated: false)
        }
    }

    deinit {
        session.removeObserver(self, forKeyPath: "outputVolume", context: &kvoContext)
    }
}
