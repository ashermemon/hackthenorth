//
//  CaptureEventTrigger.swift
//  Blind Sight
//
//  Wires the physical Volume Down button to push-to-talk via AVCaptureEventInteraction.
//
//  Availability note: AVCaptureEventInteraction needs iOS 17.2+ — one point release above
//  this project's 17.0 deployment target, so a device on exactly 17.0/17.1 won't get it.
//  SwiftUI's own .onCameraCaptureEvent modifier is NOT a lower-availability alternative here:
//  in this SDK it needs iOS 18.0+, higher than the raw UIKit class.
//
//  Confirmed on-device (iOS 18.7): even with ARSessionManager's session running with no
//  errors, this does NOT reliably intercept Volume Down — it falls through to normal system
//  volume behavior. Per Apple's docs this only fires while the app is "actively using the
//  camera," and that condition was demonstrated against a classic AVCaptureSession, not an
//  ARSession; ARKit likely doesn't register the same way despite genuinely owning the camera.
//  Left wired in as a harmless bonus in case it fires on some configuration, but
//  ContentView's on-screen "Hold to Ask" is the trigger everything actually depends on now.
//

import AVKit
import SwiftUI
import UIKit

/// Hosts a transparent UIView with an AVCaptureEventInteraction attached, so SwiftUI can react
/// to hardware button presses if the OS delivers them (see note above — not guaranteed).
struct CaptureEventTrigger: UIViewRepresentable {
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction(
                primary: { event in
                    switch event.phase {
                    case .began:
                        onPress()
                    case .ended, .cancelled:
                        onRelease()
                    @unknown default:
                        break
                    }
                },
                secondary: { _ in
                    // Volume Up: no secondary action yet (PRD leaves this open for later).
                }
            )
            // view.addInteraction retains it via its own `interactions` array — no extra storage needed.
            view.addInteraction(interaction)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
