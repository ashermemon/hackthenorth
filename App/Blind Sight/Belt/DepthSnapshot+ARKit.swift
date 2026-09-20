//
//  DepthSnapshot+ARKit.swift
//  Blind Sight
//
//  The only place the belt's depth logic touches ARKit: copies one ARFrame's LiDAR depth,
//  confidence, and camera geometry into a plain DepthSnapshot the processor can chew on a
//  background queue without holding the ARFrame (ARKit stalls if too many are retained).
//

import ARKit

extension DepthSnapshot {
    init?(frame: ARFrame) {
        guard let sceneDepth = frame.sceneDepth else { return nil }
        let depthBuffer = sceneDepth.depthMap
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        guard width > 0, height > 0,
              CVPixelBufferGetPixelFormatType(depthBuffer) == kCVPixelFormatType_DepthFloat32,
              let depth = Self.copyPlane(of: depthBuffer, width: width, height: height, as: Float.self, fill: 0)
        else { return nil }

        var confidence: [UInt8]?
        if let confidenceBuffer = sceneDepth.confidenceMap,
           CVPixelBufferGetWidth(confidenceBuffer) == width,
           CVPixelBufferGetHeight(confidenceBuffer) == height {
            confidence = Self.copyPlane(of: confidenceBuffer, width: width, height: height, as: UInt8.self, fill: 0)
        }

        // ARCamera.intrinsics are in RGB-image pixels; the depth map is a smaller version of
        // the same view, so scale them down to depth-map pixels.
        let image = frame.camera.imageResolution
        let k = frame.camera.intrinsics
        let sx = Float(width) / Float(image.width)
        let sy = Float(height) / Float(image.height)
        let geometry = DepthGeometry(
            fx: k.columns.0.x * sx, fy: k.columns.1.y * sy,
            cx: k.columns.2.x * sx, cy: k.columns.2.y * sy,
            cameraToWorld: frame.camera.transform
        )
        self.init(width: width, height: height, depth: depth, confidence: confidence, geometry: geometry)
    }

    /// Copies a single-plane pixel buffer into a tightly packed array, honoring row padding.
    private static func copyPlane<T>(of buffer: CVPixelBuffer, width: Int, height: Int, as: T.Type, fill: T) -> [T]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let rowLength = width * MemoryLayout<T>.stride
        guard rowBytes >= rowLength else { return nil }
        var out = [T](repeating: fill, count: width * height)
        out.withUnsafeMutableBytes { destination in
            for row in 0..<height {
                memcpy(destination.baseAddress! + row * rowLength, base + row * rowBytes, rowLength)
            }
        }
        return out
    }
}
