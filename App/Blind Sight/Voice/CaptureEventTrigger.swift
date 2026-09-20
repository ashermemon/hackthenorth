//
//  CaptureEventTrigger.swift
//  Blind Sight
//
//  Wires the physical Volume Down button to push-to-talk via AVCaptureEventInteraction.
//
//  Availability note: AVCaptureEventInteraction needs iOS 17.2+ — one point release above
//  this project's 17.0 deployment target, so a device on exactly 17.0/17.1 won't get it.
//  SwiftUI's own .onCameraCaptureEvent modifier is NOT a lower-availability alternative here:
//  in this SDK it needs iOS 18.0+, higher than the raw UIKit class. Below 17.2, this attaches
//  nothing at all — ContentView shows an on-screen "Hold to Ask" fallback instead, per the
//  PRD's own stated mitigation for this exact trigger being unreliable/unavailable.
//

import AVKit
import SwiftUI
import UIKit

/// Hosts an invisible UIView with an AVCaptureEventInteraction attached, so SwiftUI can react
/// to hardware button presses. Per Apple's docs, this only fires while the app is actively
/// using the camera — ARSessionManager's session (started in ContentView) covers that.
struct CaptureEventTrigger: UIViewRepresentable {
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true

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
