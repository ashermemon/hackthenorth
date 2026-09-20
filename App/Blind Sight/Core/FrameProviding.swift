//
//  FrameProviding.swift
//  Blind Sight
//
//  Lets the voice pipeline depend on "give me a JPEG frame" instead of on ARSessionManager
//  directly, so it can be built and tested in Simulator — where ARKit's sceneDepth/LiDAR
//  path never runs — without waiting on real device time.
//

import CoreImage
import CoreVideo
import UIKit

protocol FrameProviding: AnyObject {
    /// The current camera frame as JPEG, or nil if none has arrived yet. Grab this once per
    /// voice query (on button release), not continuously — matches the PRD's "only grabbed
    /// and sent to Gemini when a voice query fires."
    var latestJPEG: Data? { get }
}

extension ARSessionManager: FrameProviding {
    private static let jpegContext = CIContext()

    var latestJPEG: Data? {
        guard let pixelBuffer = latestFrame?.capturedImage else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = Self.jpegContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }
}

/// Test double for voice-pipeline work with no camera/ARKit available (Simulator, unit
/// tests, or just iterating before the belt owner has ARSessionManager verified on device).
/// Pass a bundled asset name to use a real photo, otherwise falls back to a synthesized
/// placeholder so `latestJPEG` is always non-nil.
final class MockFrameProvider: FrameProviding {
    let latestJPEG: Data?

    init(imageName: String? = nil) {
        if let imageName, let image = UIImage(named: imageName) {
            latestJPEG = image.jpegData(compressionQuality: 0.8)
        } else {
            latestJPEG = Self.placeholder.jpegData(compressionQuality: 0.8)
        }
    }

    private static let placeholder: UIImage = {
        let size = CGSize(width: 640, height: 480)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.darkGray.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let text = "MockFrameProvider — no camera frame"
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 20)
            ]
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attrs
            )
        }
    }()
}
