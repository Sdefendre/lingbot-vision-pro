import Foundation
import simd

/// Procedurally synthesizes streaming reconstruction frames that *feel* like
/// LingBot-Map outputs (poses + dense colored points + confidence + keyframes).
///
/// This powers the Vision Pro demo without requiring a CUDA GPU on-device.
/// Export real NPZ/PLY from `lingbot-map` and drop them in Resources for live data.
enum DemoSceneGenerator {

    static func generate(scene: DemoSceneKind) -> [StreamFrame] {
        switch scene {
        case .courthouse: return generateArchitectural(scene: scene, radius: 4.2, floors: 2.2, columns: 8)
        case .university: return generateArchitectural(scene: scene, radius: 5.5, floors: 3.0, columns: 12)
        case .loop: return generateLoop(scene: scene)
        case .oxford: return generateOutdoor(scene: scene, scale: 8.0)
        case .indoorWalkthrough: return generateIndoor(scene: scene)
        case .aerial: return generateAerial(scene: scene)
        }
    }

    // MARK: - Architectural exterior (courthouse / university)

    private static func generateArchitectural(scene: DemoSceneKind, radius: Float, floors: Float, columns: Int) -> [StreamFrame] {
        var frames: [StreamFrame] = []
        let n = scene.frameCount
        let ppf = scene.pointsPerFrame
        let kf = scene.keyframeInterval

        for i in 0..<n {
            let t = Float(i) / Float(max(n - 1, 1))
            let angle = t * (.pi * 1.35) + 0.4
            let camPos = SIMD3<Float>(
                cos(angle) * (radius + 2.8),
                1.55 + sin(t * .pi) * 0.25,
                sin(angle) * (radius + 2.8)
            )
            let lookAt = SIMD3<Float>(0, floors * 0.45, 0)
            let pose = makePose(id: i, from: camPos, lookingAt: lookAt, keyframe: i % kf == 0)

            var points: [ReconPoint] = []
            points.reserveCapacity(ppf)

            // Facade wall grid
            let wallCount = ppf / 2
            for j in 0..<wallCount {
                let u = Float(j % 40) / 39.0
                let v = Float(j / 40) / max(Float(wallCount / 40), 1)
                let theta = u * .pi * 1.1 - 0.2
                let y = v * floors
                let r = radius + hashNoise(i, j) * 0.08
                let p = SIMD3<Float>(cos(theta) * r, y, sin(theta) * r)
                let stone = SIMD3<Float>(0.72, 0.68, 0.58) + SIMD3(repeating: hashNoise(j, i) * 0.12)
                points.append(ReconPoint(position: p, color: saturate(stone), confidence: 0.55 + hashNoise(i + j, 3) * 0.4))
            }

            // Columns
            for c in 0..<columns {
                let a = Float(c) / Float(columns) * .pi * 1.05
                for h in 0..<12 {
                    let y = Float(h) / 11.0 * floors * 0.9
                    let base = SIMD3<Float>(cos(a) * radius * 0.92, y, sin(a) * radius * 0.92)
                    for k in 0..<3 {
                        let offset = SIMD3<Float>(hashNoise(c, k) * 0.12, 0, hashNoise(k, c) * 0.12)
                        points.append(ReconPoint(
                            position: base + offset,
                            color: SIMD3(0.85, 0.82, 0.75),
                            confidence: 0.8
                        ))
                    }
                }
            }

            // Ground plane near camera view
            let groundN = min(ppf / 4, points.capacity - points.count)
            for j in 0..<max(groundN, 0) {
                let gx = (hashNoise(j, i) - 0.5) * radius * 2.4
                let gz = (hashNoise(i, j) - 0.5) * radius * 2.4
                let green = SIMD3<Float>(0.25, 0.42 + hashNoise(j, 9) * 0.15, 0.22)
                points.append(ReconPoint(position: SIMD3(gx, 0.01, gz), color: green, confidence: 0.7))
            }

            // Sky-ish distant points (low confidence; filtered when maskSky)
            if !scene.maskSky {
                for j in 0..<40 {
                    let a = hashNoise(j, i + 50) * .pi * 2
                    let p = SIMD3<Float>(cos(a) * 20, 8 + hashNoise(i, j) * 6, sin(a) * 20)
                    points.append(ReconPoint(position: p, color: SIMD3(0.55, 0.7, 0.95), confidence: 0.15))
                }
            }

            frames.append(StreamFrame(frameIndex: i, pose: pose, points: points, timestamp: Double(i) / 18.0))
        }
        return frames
    }

    // MARK: - Loop closure path

    private static func generateLoop(scene: DemoSceneKind) -> [StreamFrame] {
        var frames: [StreamFrame] = []
        let n = scene.frameCount
        let ppf = scene.pointsPerFrame
        let kf = scene.keyframeInterval
        let pathRadius: Float = 4.5

        for i in 0..<n {
            let t = Float(i) / Float(max(n - 1, 1))
            let angle = t * .pi * 2
            let camPos = SIMD3<Float>(cos(angle) * pathRadius, 1.5, sin(angle) * pathRadius)
            let tangent = SIMD3<Float>(-sin(angle), 0, cos(angle))
            let lookAt = camPos + tangent * 1.5 + SIMD3(0, -0.2, 0)
            let pose = makePose(id: i, from: camPos, lookingAt: lookAt, keyframe: i % kf == 0)

            var points: [ReconPoint] = []
            // Corridor walls forming a ring
            for j in 0..<ppf {
                let side: Float = j % 2 == 0 ? 1 : -1
                let along = Float(j) / Float(ppf) * .pi * 2
                let localR = pathRadius + side * 1.2
                let y = (hashNoise(j, i) * 2.4)
                var p = SIMD3<Float>(cos(along) * localR, y, sin(along) * localR)
                // slight drift that corrects near loop end
                if t < 0.85 {
                    p += SIMD3(hashNoise(i, j) * 0.05, 0, hashNoise(j, i) * 0.05)
                }
                let wall = SIMD3<Float>(0.55 + hashNoise(j, 1) * 0.2, 0.5, 0.48)
                let conf: Float = t > 0.9 ? 0.9 : 0.5 + hashNoise(i + j, 2) * 0.35
                points.append(ReconPoint(position: p, color: wall, confidence: conf))
            }

            // Floor
            for j in 0..<(ppf / 5) {
                let a = hashNoise(j, i) * .pi * 2
                let r = hashNoise(i, j) * (pathRadius + 1)
                points.append(ReconPoint(
                    position: SIMD3(cos(a) * r, 0.02, sin(a) * r),
                    color: SIMD3(0.4, 0.38, 0.36),
                    confidence: 0.75
                ))
            }

            frames.append(StreamFrame(frameIndex: i, pose: pose, points: points, timestamp: Double(i) / 18.0))
        }
        return frames
    }

    // MARK: - Outdoor large scale

    private static func generateOutdoor(scene: DemoSceneKind, scale: Float) -> [StreamFrame] {
        var frames: [StreamFrame] = []
        let n = scene.frameCount
        let ppf = scene.pointsPerFrame
        let kf = scene.keyframeInterval

        for i in 0..<n {
            let t = Float(i) / Float(max(n - 1, 1))
            let camPos = SIMD3<Float>(t * scale * 1.6 - scale * 0.3, 1.7, sin(t * 4) * 2.2)
            let lookAt = camPos + SIMD3(1.5, -0.15, cos(t * 3) * 0.5)
            let pose = makePose(id: i, from: camPos, lookingAt: lookAt, keyframe: i % kf == 0)

            var points: [ReconPoint] = []
            for j in 0..<ppf {
                let x = (hashNoise(j, i) - 0.2) * scale * 1.8 + t * scale * 0.5
                let z = (hashNoise(i, j) - 0.5) * scale
                // Terrain height field
                let y = sin(x * 0.35) * 0.4 + cos(z * 0.25) * 0.35 + hashNoise(j, i) * 0.08
                let grass = SIMD3<Float>(0.22, 0.45 + hashNoise(j, 4) * 0.2, 0.18)
                let stone = SIMD3<Float>(0.5, 0.48, 0.45)
                let isStructure = hashNoise(j * 3, i) > 0.82
                let p = SIMD3<Float>(x, isStructure ? y + hashNoise(j, 7) * 3.5 : y, z)
                points.append(ReconPoint(
                    position: p,
                    color: isStructure ? stone : grass,
                    confidence: isStructure ? 0.85 : 0.55 + hashNoise(i, j) * 0.3
                ))
            }
            frames.append(StreamFrame(frameIndex: i, pose: pose, points: points, timestamp: Double(i) / 16.0))
        }
        return frames
    }

    // MARK: - Indoor walkthrough

    private static func generateIndoor(scene: DemoSceneKind) -> [StreamFrame] {
        var frames: [StreamFrame] = []
        let n = scene.frameCount
        let ppf = scene.pointsPerFrame
        let kf = scene.keyframeInterval
        let roomLen: Float = 14
        let roomW: Float = 4.2
        let roomH: Float = 2.7

        for i in 0..<n {
            let t = Float(i) / Float(max(n - 1, 1))
            // Path through corridor then left into living space
            let camPos: SIMD3<Float>
            let lookAt: SIMD3<Float>
            if t < 0.55 {
                let x = t / 0.55 * roomLen
                camPos = SIMD3(x, 1.55, 0)
                lookAt = SIMD3(x + 1.2, 1.4, sin(t * 8) * 0.3)
            } else {
                let u = (t - 0.55) / 0.45
                camPos = SIMD3(roomLen * 0.75, 1.55, u * roomW * 1.4)
                lookAt = SIMD3(roomLen * 0.75 + sin(u * 3), 1.3, u * roomW * 1.4 + 1.0)
            }
            let pose = makePose(id: i, from: camPos, lookingAt: lookAt, keyframe: i % kf == 0)

            var points: [ReconPoint] = []
            // Walls, floor, ceiling samples near camera
            for j in 0..<ppf {
                let kind = j % 5
                let noise = hashNoise(i, j)
                switch kind {
                case 0: // floor
                    let x = camPos.x + (noise - 0.5) * 3.5
                    let z = camPos.z + (hashNoise(j, i) - 0.5) * 3.5
                    points.append(ReconPoint(position: SIMD3(x, 0.02, z), color: SIMD3(0.55, 0.45, 0.35), confidence: 0.8))
                case 1: // left wall
                    let x = camPos.x + (noise - 0.5) * 3
                    let y = hashNoise(j, 2) * roomH
                    points.append(ReconPoint(position: SIMD3(x, y, -roomW * 0.5), color: SIMD3(0.85, 0.84, 0.8), confidence: 0.75))
                case 2: // right wall
                    let x = camPos.x + (noise - 0.5) * 3
                    let y = hashNoise(j, 3) * roomH
                    points.append(ReconPoint(position: SIMD3(x, y, roomW * 0.5), color: SIMD3(0.82, 0.83, 0.8), confidence: 0.75))
                case 3: // ceiling
                    let x = camPos.x + (noise - 0.5) * 3
                    let z = camPos.z + (hashNoise(j, 4) - 0.5) * 2
                    points.append(ReconPoint(position: SIMD3(x, roomH, z), color: SIMD3(0.92, 0.92, 0.9), confidence: 0.65))
                default: // furniture blobs
                    let fx = camPos.x + (noise - 0.5) * 2
                    let fz = (hashNoise(j, 5) > 0.5 ? 1 : -1) * (1.0 + hashNoise(j, 6))
                    let fy = hashNoise(j, 7) * 0.9
                    let wood = SIMD3<Float>(0.45, 0.28, 0.15)
                    points.append(ReconPoint(position: SIMD3(fx, fy, camPos.z + fz * 0.4), color: wood, confidence: 0.7))
                }
            }
            frames.append(StreamFrame(frameIndex: i, pose: pose, points: points, timestamp: Double(i) / 20.0))
        }
        return frames
    }

    // MARK: - Aerial

    private static func generateAerial(scene: DemoSceneKind) -> [StreamFrame] {
        var frames: [StreamFrame] = []
        let n = scene.frameCount
        let ppf = scene.pointsPerFrame
        let kf = scene.keyframeInterval

        for i in 0..<n {
            let t = Float(i) / Float(max(n - 1, 1))
            let angle = t * .pi * 2
            let camPos = SIMD3<Float>(cos(angle) * 6, 7.5 - t * 1.5, sin(angle) * 6)
            let pose = makePose(id: i, from: camPos, lookingAt: SIMD3(0, 0, 0), keyframe: i % kf == 0)

            var points: [ReconPoint] = []
            for j in 0..<ppf {
                let x = (hashNoise(j, i) - 0.5) * 14
                let z = (hashNoise(i, j) - 0.5) * 14
                let building = hashNoise(j * 2, i * 3) > 0.7
                let h = building ? 0.5 + hashNoise(j, 8) * 4.0 : hashNoise(j, 9) * 0.3
                let color: SIMD3<Float> = building
                    ? SIMD3(0.55 + hashNoise(j, 1) * 0.2, 0.52, 0.5)
                    : SIMD3(0.2, 0.5, 0.22)
                points.append(ReconPoint(position: SIMD3(x, h, z), color: color, confidence: 0.6 + hashNoise(i, j) * 0.35))
            }
            frames.append(StreamFrame(frameIndex: i, pose: pose, points: points, timestamp: Double(i) / 15.0))
        }
        return frames
    }

    // MARK: - Helpers

    private static func makePose(id: Int, from: SIMD3<Float>, lookingAt: SIMD3<Float>, keyframe: Bool) -> CameraPose {
        let forward = simd_normalize(lookingAt - from)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(forward, worldUp))
        let up = simd_normalize(simd_cross(right, forward))
        // Build rotation looking down -Z in RealityKit-ish convention
        let rot = simd_quatf(from: SIMD3(0, 0, -1), to: forward)
        // Stabilize with up hint when possible
        let _ = up
        return CameraPose(id: id, frameIndex: id, position: from, rotation: rot, isKeyframe: keyframe)
    }

    /// Deterministic pseudo-noise in 0…1
    private static func hashNoise(_ a: Int, _ b: Int) -> Float {
        var x = UInt32(bitPattern: Int32(truncatingIfNeeded: a &* 374_761_393 &+ b &* 668_265_263))
        x = (x ^ (x >> 13)) &* 1_274_126_177
        x = x ^ (x >> 16)
        return Float(x % 10_000) / 10_000.0
    }

    private static func saturate(_ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(min(max(v.x, 0), 1), min(max(v.y, 0), 1), min(max(v.z, 0), 1))
    }
}
