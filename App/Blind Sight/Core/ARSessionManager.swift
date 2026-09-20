//
//  ARSessionManager.swift
//  Blind Sight
//
//  Shared by Belt/ and Voice/ — do not fork a second ARSession.
//

import ARKit
import Combine

/// The one ARKit session for the whole app. LiDAR depth, RGB, and pose all arrive together
/// in each `ARFrame`, so the belt loop and the voice pipeline both read `latestFrame` here
/// instead of each running their own capture session (PRD "System Architecture" / "Inputs" —
/// RGB "arrives in every ARKit frame alongside depth, one shared session, not a separate
/// on/off capture"). This is also the active capture session the button-trigger API
/// (`AVCaptureEventInteraction`) needs to be running in order to fire.
final class ARSessionManager: NSObject, ObservableObject, ARSessionDelegate {
    static let shared = ARSessionManager()

    let session = ARSession()

    @Published private(set) var latestFrame: ARFrame?
    @Published private(set) var isRunning = false
    @Published private(set) var trackingState: ARCamera.TrackingState = .notAvailable

    private override init() {
        super.init()
        session.delegate = self
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        session.run(config)
        isRunning = true
    }

    func stop() {
        session.pause()
        isRunning = false
    }

    // MARK: - ARSessionDelegate
    //
    // ARKit does not guarantee these fire on the main thread. `@Published` mutations must
    // land on main (SwiftUI/Combine requirement), so every delegate callback hops explicitly
    // rather than relying on whichever queue ARKit happens to call from. Keep these bodies
    // cheap — anything slow here delays the next frame delivery, which the belt loop depends
    // on running at a steady rate.

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async { [weak self] in
            self?.latestFrame = frame
            self?.trackingState = frame.camera.trackingState
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
        }
    }
}
