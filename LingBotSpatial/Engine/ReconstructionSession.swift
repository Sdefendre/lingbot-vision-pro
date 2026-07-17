import Foundation
import Observation
import simd
import SwiftUI

/// Central observable session: loads a demo scene, streams frames like LingBot-Map,
/// and exposes aggregated geometry for RealityKit renderers.
@Observable
@MainActor
final class ReconstructionSession {
    // Scene selection
    var selectedScene: DemoSceneKind = .courthouse
    var playback: PlaybackState = .idle
    var settings = ReconstructionSettings()

    // Immersion
    var isImmersiveOpen = false
    var isVolumeOpen = false
    var immersionMode: ImmersionMode = .mixed

    // Stream state
    private(set) var frames: [StreamFrame] = []
    private(set) var currentFrameIndex: Int = 0
    private(set) var accumulatedPoints: [ReconPoint] = []
    private(set) var poses: [CameraPose] = []
    private(set) var keyframePoses: [CameraPose] = []
    private(set) var loadProgress: Double = 0
    private(set) var streamFPSActual: Double = 0
    private(set) var totalPointCount: Int = 0
    private(set) var visiblePointCount: Int = 0
    private(set) var statusMessage: String = "Select a scene to begin"

    // Bounds for framing
    private(set) var boundsMin = SIMD3<Float>(repeating: 0)
    private(set) var boundsMax = SIMD3<Float>(repeating: 0)
    var boundsCenter: SIMD3<Float> { (boundsMin + boundsMax) * 0.5 }
    var boundsExtent: SIMD3<Float> { boundsMax - boundsMin }

    // Generation token to cancel in-flight loads
    private var loadToken = UUID()
    private var streamTask: Task<Void, Never>?
    private var lastFrameTime: Date?

    var progress: Double {
        guard !frames.isEmpty else { return 0 }
        return Double(currentFrameIndex) / Double(max(frames.count - 1, 1))
    }

    var currentPose: CameraPose? {
        poses.last
    }

    var isPlaying: Bool {
        playback == .streaming
    }

    // MARK: - Lifecycle

    func selectScene(_ scene: DemoSceneKind) {
        selectedScene = scene
        stopStreaming()
        frames = []
        resetGeometry()
        playback = .idle
        statusMessage = "Ready · \(scene.title)"
    }

    func loadSelectedScene() async {
        let token = UUID()
        loadToken = token
        stopStreaming()
        resetGeometry()
        playback = .loading
        loadProgress = 0
        statusMessage = "Synthesizing geometric context…"

        let scene = selectedScene
        // Generate off main actor-ish via detached
        let generated = await Task.detached(priority: .userInitiated) {
            DemoSceneGenerator.generate(scene: scene)
        }.value

        guard loadToken == token else { return }

        frames = generated
        loadProgress = 1
        playback = .ready
        statusMessage = "\(generated.count) frames ready · tap Play or Enter Immersive"
        // Seed first frame so volume isn't empty
        if let first = generated.first {
            applyFrame(first, appendOnly: false)
        }
    }

    func play() {
        guard !frames.isEmpty else {
            Task { await loadSelectedScene(); play() }
            return
        }
        if playback == .completed || currentFrameIndex >= frames.count - 1 {
            resetGeometry()
            currentFrameIndex = 0
            if let first = frames.first { applyFrame(first, appendOnly: false) }
        }
        playback = .streaming
        statusMessage = "Streaming reconstruction…"
        startStreamLoop()
    }

    func pause() {
        streamTask?.cancel()
        streamTask = nil
        if playback == .streaming {
            playback = .paused
            statusMessage = "Paused at frame \(currentFrameIndex)"
        }
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    func reset() {
        stopStreaming()
        resetGeometry()
        currentFrameIndex = 0
        if let first = frames.first {
            applyFrame(first, appendOnly: false)
            playback = .ready
        } else {
            playback = .idle
        }
        statusMessage = "Reset"
    }

    func seek(to fraction: Double) {
        guard !frames.isEmpty else { return }
        let wasPlaying = isPlaying
        pause()
        let idx = Int(fraction * Double(frames.count - 1))
        rebuild(upTo: idx)
        if wasPlaying { play() }
    }

    func stepForward() {
        guard currentFrameIndex + 1 < frames.count else { return }
        let next = frames[currentFrameIndex + 1]
        applyFrame(next, appendOnly: true)
        currentFrameIndex += 1
        if currentFrameIndex >= frames.count - 1 {
            playback = .completed
            statusMessage = "Reconstruction complete · \(totalPointCount) points"
        }
    }

    // MARK: - Filtering for renderers

    /// Points currently visible given confidence / keyframe settings.
    func filteredPoints(limit: Int = 80_000) -> [ReconPoint] {
        let thr = settings.confidenceThreshold
        let step = max(settings.downsample, 1)
        var out: [ReconPoint] = []
        out.reserveCapacity(min(accumulatedPoints.count / step, limit))
        var i = 0
        while i < accumulatedPoints.count && out.count < limit {
            let p = accumulatedPoints[i]
            if p.confidence >= thr {
                out.append(colorMapped(p))
            }
            i += step
        }
        visiblePointCount = out.count
        return out
    }

    func colorMapped(_ p: ReconPoint) -> ReconPoint {
        switch settings.colorMode {
        case .rgb:
            return p
        case .confidence:
            let c = confColor(p.confidence)
            return ReconPoint(position: p.position, color: c, confidence: p.confidence)
        case .height:
            let extentY = max(boundsExtent.y, 0.001)
            let t = (p.position.y - boundsMin.y) / extentY
            return ReconPoint(position: p.position, color: heightColor(t), confidence: p.confidence)
        case .frameAge:
            // Approximate age via confidence jitter; use relative y for demo
            let t = Float(currentFrameIndex) / Float(max(frames.count, 1))
            return ReconPoint(position: p.position, color: SIMD3(t, 0.4, 1 - t), confidence: p.confidence)
        }
    }

    // MARK: - Internals

    private func startStreamLoop() {
        streamTask?.cancel()
        lastFrameTime = Date()
        streamTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let fps = max(self.settings.streamFPS, 1)
                let delay = 1.0 / fps
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.tick()
                }
                if self.playback != .streaming { break }
            }
        }
    }

    private func tick() {
        guard currentFrameIndex + 1 < frames.count else {
            playback = .completed
            stopStreaming()
            statusMessage = "Done · \(totalPointCount.formatted()) points · \(poses.count) poses"
            return
        }
        let now = Date()
        if let last = lastFrameTime {
            let dt = now.timeIntervalSince(last)
            if dt > 0 { streamFPSActual = (streamFPSActual * 0.8) + (0.2 / dt) }
        }
        lastFrameTime = now
        stepForward()
        statusMessage = "Frame \(currentFrameIndex + 1)/\(frames.count) · \(totalPointCount.formatted()) pts"
    }

    private func rebuild(upTo index: Int) {
        resetGeometry()
        let end = min(max(index, 0), frames.count - 1)
        for i in 0...end {
            applyFrame(frames[i], appendOnly: i > 0)
        }
        currentFrameIndex = end
        playback = .paused
        statusMessage = "Seek → frame \(end + 1)/\(frames.count)"
    }

    private func applyFrame(_ frame: StreamFrame, appendOnly: Bool) {
        if !appendOnly {
            accumulatedPoints = frame.points
            poses = [frame.pose]
            keyframePoses = frame.pose.isKeyframe ? [frame.pose] : []
        } else {
            // Keep keyframe density higher; subsample non-keyframes
            if frame.pose.isKeyframe || !settings.showKeyframesOnly {
                accumulatedPoints.append(contentsOf: frame.points)
            }
            poses.append(frame.pose)
            if frame.pose.isKeyframe { keyframePoses.append(frame.pose) }
            // Cap memory for long sequences
            let maxPoints = 120_000
            if accumulatedPoints.count > maxPoints {
                accumulatedPoints = Array(accumulatedPoints.suffix(maxPoints))
            }
        }
        totalPointCount = accumulatedPoints.count
        recomputeBounds()
        currentFrameIndex = frame.frameIndex
    }

    private func resetGeometry() {
        accumulatedPoints = []
        poses = []
        keyframePoses = []
        totalPointCount = 0
        visiblePointCount = 0
        boundsMin = .zero
        boundsMax = .zero
        currentFrameIndex = 0
        streamFPSActual = 0
    }

    private func recomputeBounds() {
        guard let first = accumulatedPoints.first else {
            boundsMin = .zero
            boundsMax = .zero
            return
        }
        var mn = first.position
        var mx = first.position
        // Stride for speed
        let step = max(accumulatedPoints.count / 2000, 1)
        var i = 0
        while i < accumulatedPoints.count {
            let p = accumulatedPoints[i].position
            mn = simd_min(mn, p)
            mx = simd_max(mx, p)
            i += step
        }
        boundsMin = mn
        boundsMax = mx
    }

    private func confColor(_ c: Float) -> SIMD3<Float> {
        // blue → cyan → green → yellow → red
        let t = min(max(c, 0), 1)
        if t < 0.25 {
            let u = t / 0.25
            return SIMD3(0, u, 1)
        } else if t < 0.5 {
            let u = (t - 0.25) / 0.25
            return SIMD3(0, 1, 1 - u)
        } else if t < 0.75 {
            let u = (t - 0.5) / 0.25
            return SIMD3(u, 1, 0)
        } else {
            let u = (t - 0.75) / 0.25
            return SIMD3(1, 1 - u, 0)
        }
    }

    private func heightColor(_ t: Float) -> SIMD3<Float> {
        let u = min(max(t, 0), 1)
        return SIMD3(u, 0.3 + (1 - u) * 0.5, 1 - u)
    }
}
