import Foundation
import simd
import SwiftUI

// MARK: - Core Geometry Types

/// A single reconstructed 3D point with color and confidence (mirrors LingBot-Map outputs).
struct ReconPoint: Sendable, Equatable {
    var position: SIMD3<Float>
    var color: SIMD3<Float>   // RGB 0…1
    var confidence: Float     // higher = more reliable geometry

    static func == (lhs: ReconPoint, rhs: ReconPoint) -> Bool {
        lhs.position == rhs.position
    }
}

/// Estimated camera pose for one streaming frame (c2w).
struct CameraPose: Sendable, Equatable, Identifiable {
    var id: Int
    var frameIndex: Int
    var position: SIMD3<Float>
    var rotation: simd_quatf
    var isKeyframe: Bool

    var transform: simd_float4x4 {
        simd_float4x4(rotation) * simd_float4x4(translation: position)
    }

    var lookDirection: SIMD3<Float> {
        simd_act(rotation, SIMD3<Float>(0, 0, -1))
    }
}

/// One streaming inference step — what LingBot-Map would emit per frame.
struct StreamFrame: Sendable, Identifiable {
    var id: Int { frameIndex }
    var frameIndex: Int
    var pose: CameraPose
    var points: [ReconPoint]
    var timestamp: TimeInterval
}

// MARK: - Demo Scenes

enum DemoSceneKind: String, CaseIterable, Identifiable, Codable {
    case courthouse
    case university
    case loop
    case oxford
    case indoorWalkthrough
    case aerial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .courthouse: return "Courthouse"
        case .university: return "University"
        case .loop: return "Loop Closure"
        case .oxford: return "Oxford Spires"
        case .indoorWalkthrough: return "Indoor Walkthrough"
        case .aerial: return "Aerial Survey"
        }
    }

    var subtitle: String {
        switch self {
        case .courthouse: return "Outdoor landmark · sky-masked"
        case .university: return "Campus walk · mid-scale"
        case .loop: return "Trajectory with loop closure"
        case .oxford: return "Large outdoor scene"
        case .indoorWalkthrough: return "Long indoor sequence"
        case .aerial: return "Top-down large-scale map"
        }
    }

    var systemImage: String {
        switch self {
        case .courthouse: return "building.columns.fill"
        case .university: return "building.2.fill"
        case .loop: return "arrow.triangle.2.circlepath"
        case .oxford: return "mountain.2.fill"
        case .indoorWalkthrough: return "house.fill"
        case .aerial: return "airplane"
        }
    }

    var accent: Color {
        switch self {
        case .courthouse: return Color(red: 0.95, green: 0.55, blue: 0.25)
        case .university: return Color(red: 0.30, green: 0.55, blue: 0.95)
        case .loop: return Color(red: 0.45, green: 0.85, blue: 0.55)
        case .oxford: return Color(red: 0.55, green: 0.40, blue: 0.90)
        case .indoorWalkthrough: return Color(red: 0.95, green: 0.40, blue: 0.55)
        case .aerial: return Color(red: 0.20, green: 0.80, blue: 0.85)
        }
    }

    var frameCount: Int {
        switch self {
        case .courthouse: return 120
        case .university: return 140
        case .loop: return 160
        case .oxford: return 180
        case .indoorWalkthrough: return 220
        case .aerial: return 100
        }
    }

    var pointsPerFrame: Int {
        switch self {
        case .indoorWalkthrough: return 900
        case .aerial: return 1200
        default: return 750
        }
    }

    var keyframeInterval: Int {
        switch self {
        case .indoorWalkthrough: return 4
        case .oxford, .aerial: return 3
        default: return 2
        }
    }

    var maskSky: Bool {
        switch self {
        case .courthouse, .university, .oxford, .aerial: return true
        default: return false
        }
    }

    var blurb: String {
        switch self {
        case .courthouse:
            return "Feed-forward reconstruction of a classical exterior with sky masking for clean geometry."
        case .university:
            return "Campus path streaming with Geometric Context Transformer anchor windows."
        case .loop:
            return "Closed loop trajectory demonstrating drift correction via trajectory memory."
        case .oxford:
            return "Large-scale outdoor reconstruction inspired by Oxford Spires benchmarks."
        case .indoorWalkthrough:
            return "Long indoor walkthrough — keyframe-sparse streaming over hundreds of frames."
        case .aerial:
            return "Bird’s-eye style map build with wide FOV and deep range."
        }
    }
}

// MARK: - Playback / Session State

enum PlaybackState: Equatable {
    case idle
    case loading
    case ready
    case streaming
    case paused
    case completed
    case failed(String)
}

enum ImmersionMode: String, CaseIterable, Identifiable {
    case mixed
    case progressive
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed: return "Mixed"
        case .progressive: return "Progressive"
        case .full: return "Full"
        }
    }

    var systemImage: String {
        switch self {
        case .mixed: return "circle.lefthalf.filled"
        case .progressive: return "circle.bottomhalf.filled"
        case .full: return "circle.fill"
        }
    }
}

enum PointColorMode: String, CaseIterable, Identifiable {
    case rgb
    case confidence
    case height
    case frameAge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rgb: return "RGB"
        case .confidence: return "Confidence"
        case .height: return "Height"
        case .frameAge: return "Stream Age"
        }
    }
}

// MARK: - Session Settings

struct ReconstructionSettings: Equatable {
    var confidenceThreshold: Float = 0.35
    var pointScale: Float = 0.012
    var showTrajectory: Bool = true
    var showFrustums: Bool = true
    var showKeyframesOnly: Bool = false
    var streamFPS: Double = 18
    var colorMode: PointColorMode = .rgb
    var downsample: Int = 1
    var autoOrbit: Bool = false
    var followCamera: Bool = true
}

// MARK: - Matrix helpers

extension simd_float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
    }

    init(_ q: simd_quatf) {
        self = matrix_float4x4(q)
    }
}
