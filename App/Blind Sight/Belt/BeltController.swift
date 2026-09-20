//
//  BeltController.swift
//  Blind Sight
//
//  Sensing & belt control loop owner.
//

import ARKit
import Combine
import UIKit

/// Owns the depth -> belt zone/intensity loop (PRD "Processing" -> "Depth -> belt zone/intensity"):
/// a few times per second (`AppConfig.beltUpdateHz`) it copies the latest LiDAR frame off
/// `ARSessionManager.shared`, works out the nearest obstacle per zone on a background queue,
/// turns that into PWM duties, and sends them to the ESP32 over UDP.
///
/// It never waits on the voice pipeline (they share only the ARSession), and if a tick's depth
/// work is still running when the next tick fires, that tick is skipped instead of queued, so a
/// slow frame can't build a backlog of stale belt updates.
final class BeltController: ObservableObject {
    static let shared = BeltController()

    /// Live tuning; the debug screen edits this and the next tick picks it up.
    @Published var tuning = BeltTuning()
    /// Nearest obstacle per zone (meters) after the persistence filter, nil = clear. This is what
    /// drives the belt, and what the debug screen shows.
    @Published private(set) var distances = [Float?](repeating: nil, count: DepthProcessor.zoneCount)
    /// What was last sent to the belt, in wire order.
    @Published private(set) var duties = [UInt8](repeating: 0, count: DepthProcessor.zoneCount)
    @Published private(set) var depthStatus = "waiting for depth"
    @Published private(set) var processingMillis = 0.0
    /// When non-nil, these duties are sent as-is and depth is ignored (link/belt testing).
    @Published var manualDuties: [UInt8]? {
        didSet {
            smoother.reset()
            distanceFilter.reset()
        }
    }

    let sender: BeltUDPSender

    private static let hostKey = "beltHostOverride"
    private let processingQueue = DispatchQueue(label: "belt.depth", qos: .userInitiated)
    private var distanceFilter = DistanceFilter()
    private var smoother = ZoneSmoother()
    private var timer: Timer?
    private var isProcessing = false
    private var sweepTask: Task<Void, Never>?

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.hostKey)
        sender = BeltUDPSender(host: saved ?? AppConfig.esp32Host)
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        // A chest-mounted phone gets no touches; if the screen locks, ARKit stops and so does the belt.
        UIApplication.shared.isIdleTimerDisabled = true
        sender.connect()
        let timer = Timer(timeInterval: 1.0 / AppConfig.beltUpdateHz, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common) // keep firing while the UI is being touched
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sweepTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        sender.send(BeltCommand.allOff)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200)) // let the last packet out
            if self.timer == nil { self.sender.disconnect() }
        }
    }

    /// Points the belt link at a different host (persisted), e.g. a Mac running the listener tool.
    /// An empty string restores `AppConfig.esp32Host`.
    func setHost(_ host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.hostKey)
            sender.connect(host: AppConfig.esp32Host)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.hostKey)
            sender.connect(host: trimmed)
        }
    }

    // MARK: - The loop

    private func tick() {
        if let manual = manualDuties {
            emit(manual)
            return
        }
        guard !isProcessing else { return }
        guard let frame = ARSessionManager.shared.latestFrame else {
            depthStatus = "no AR frame yet"
            return
        }
        // Don't act on old data: if ARKit stalls, say nothing (the ESP32 goes quiet by itself after
        // its hold timeout) rather than repeating a stale "all clear" or "obstacle".
        let age = ProcessInfo.processInfo.systemUptime - frame.timestamp
        guard age < 0.5 else {
            depthStatus = String(format: "AR frame is stale (%.1fs old)", age)
            return
        }
        guard let snapshot = DepthSnapshot(frame: frame) else {
            depthStatus = "frame has no LiDAR depth"
            return
        }

        isProcessing = true
        let tuning = self.tuning
        let started = ProcessInfo.processInfo.systemUptime
        processingQueue.async {
            let zones = DepthProcessor.zoneDistances(snapshot, tuning: tuning)
            let millis = (ProcessInfo.processInfo.systemUptime - started) * 1000
            Task { @MainActor in
                self.finish(zones, tuning: tuning, millis: millis, snapshot: snapshot)
            }
        }
    }

    private func finish(_ zones: [Float?], tuning: BeltTuning, millis: Double, snapshot: DepthSnapshot) {
        isProcessing = false
        guard manualDuties == nil else { return } // switched to manual mid-flight
        let filtered = distanceFilter.apply(zones, window: tuning.distanceWindow)
        distances = filtered
        processingMillis = millis
        depthStatus = "depth \(snapshot.width)x\(snapshot.height), \(String(format: "%.1f", millis)) ms"
        let targets = filtered.map { IntensityMapper.duty(forDistance: $0, tuning: tuning) }
        emit(smoother.apply(targets, tuning: tuning))
    }

    private func emit(_ zoneDuties: [UInt8]) {
        duties = zoneDuties
        sender.send(BeltCommand(zoneValues: zoneDuties))
    }

    // MARK: - Test pattern

    /// Ramps each zone 0 -> 255 in turn, ignoring depth: a quick "does every motor answer, in the
    /// right order" check for the belt, and a way to test the link with no obstacle handy.
    func runSweepTest() {
        sweepTask?.cancel()
        sweepTask = Task { @MainActor in
            for zone in 0..<DepthProcessor.zoneCount {
                for step in 0...20 {
                    if Task.isCancelled { return }
                    var values = [UInt8](repeating: 0, count: DepthProcessor.zoneCount)
                    values[zone] = UInt8(step * 255 / 20)
                    manualDuties = values
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            manualDuties = nil
        }
    }
}
