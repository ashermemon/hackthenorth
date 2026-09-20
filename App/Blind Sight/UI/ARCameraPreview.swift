//
//  ARCameraPreview.swift
//  Blind Sight
//
//  Live camera passthrough for the depth-view demo screen, using ARKit's own camera-background
//  rendering rather than hand-converting CVPixelBuffers every frame. This view only ever
//  *attaches* to the app's one ARSession (ARSessionManager.shared.session) — it must never call
//  session.run()/pause() itself, since ARSessionManager is the sole owner of that lifecycle and
//  the belt loop depends on it staying up regardless of which screen is on screen.
//

import ARKit
import SceneKit
import SwiftUI

struct ARCameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = ARSessionManager.shared.session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.antialiasingMode = .none
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Nothing to push down: the shared ARSession keeps driving frames on its own.
    }
}
