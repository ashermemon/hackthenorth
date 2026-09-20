//
//  DepthGridSampler.swift
//  Blind Sight
//
//  Feeds the depth-view demo screen's grid overlay. Deliberately a separate loop from
//  BeltController's — the overlay is a GPU-heavy visual aid, not something the belt depends on,
//  so it can be switched off ("Overlay: on/off") without touching belt behavior at all.
//

import ARKit
import Combine
import Foundation

@MainActor
final class DepthGridSampler: ObservableObject {
    static let columns = 5
    static let rows = 3

    @Published private(set) var cells: [DepthProcessor.GridCell] =
        Array(repeating: DepthProcessor.GridCell(distance: nil, lowConfidenceOnly: false), count: columns * rows)

    private let processingQueue = DispatchQueue(label: "belt.depthgrid", qos: .userInitiated)
    private var timer: Timer?
    private var isProcessing = false

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / AppConfig.beltUpdateHz, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !isProcessing else { return }
        guard let frame = ARSessionManager.shared.latestFrame else { return }
        let age = ProcessInfo.processInfo.systemUptime - frame.timestamp
        guard age < 0.5 else { return }
        guard let snapshot = DepthSnapshot(frame: frame) else { return }

        isProcessing = true
        let tuning = BeltController.shared.tuning
        processingQueue.async { [weak self] in
            let cells = DepthProcessor.gridDistances(snapshot, tuning: tuning, columns: Self.columns, rows: Self.rows)
            Task { @MainActor in
                self?.isProcessing = false
                self?.cells = cells
            }
        }
    }
}
