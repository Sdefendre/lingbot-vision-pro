import Foundation
import RealityKit
import simd
import UIKit

@MainActor
enum TrajectoryEntities {
    static func makeRoot() -> Entity {
        let e = Entity()
        e.name = "TrajectoryRoot"
        return e
    }

    static func rebuild(root: Entity, poses: [CameraPose], keyframes: [CameraPose], showFrustums: Bool) {
        root.children.forEach { $0.removeFromParent() }
        guard poses.count >= 1 else { return }

        // Path spheres
        let pathRoot = Entity()
        pathRoot.name = "path"
        let step = max(poses.count / 200, 1)
        for (idx, pose) in poses.enumerated() where idx % step == 0 {
            let isKF = pose.isKeyframe
            let radius: Float = isKF ? 0.025 : 0.012
            let mesh = MeshResource.generateSphere(radius: radius)
            let color = isKF
                ? UIColor(red: 1.0, green: 0.75, blue: 0.2, alpha: 1)
                : UIColor(red: 0.3, green: 0.85, blue: 1.0, alpha: 0.9)
            let mat = SimpleMaterial(color: color, roughness: 0.4, isMetallic: false)
            let ball = ModelEntity(mesh: mesh, materials: [mat])
            ball.position = pose.position
            pathRoot.addChild(ball)
        }
        root.addChild(pathRoot)

        // Connect path with thin cylinders between consecutive samples
        let linkRoot = Entity()
        linkRoot.name = "links"
        var prev: SIMD3<Float>?
        for (idx, pose) in poses.enumerated() where idx % step == 0 {
            if let p = prev {
                linkRoot.addChild(cylinder(from: p, to: pose.position, radius: 0.004, color: UIColor(white: 0.85, alpha: 0.7)))
            }
            prev = pose.position
        }
        root.addChild(linkRoot)

        // Camera frustums for recent keyframes
        if showFrustums {
            let fr = Entity()
            fr.name = "frustums"
            let recent = keyframes.suffix(12)
            for pose in recent {
                fr.addChild(frustum(at: pose, color: UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 0.85)))
            }
            // Always show latest pose frustum in cyan
            if let last = poses.last {
                fr.addChild(frustum(at: last, color: UIColor(red: 0.2, green: 0.95, blue: 1.0, alpha: 1)))
            }
            root.addChild(fr)
        }
    }

    private static func frustum(at pose: CameraPose, color: UIColor) -> Entity {
        let root = Entity()
        root.position = pose.position
        root.orientation = pose.rotation

        let depth: Float = 0.35
        let hw: Float = 0.16
        let hh: Float = 0.1
        let origin = SIMD3<Float>(0, 0, 0)
        let corners = [
            SIMD3<Float>(-hw, -hh, -depth),
            SIMD3<Float>(hw, -hh, -depth),
            SIMD3<Float>(hw, hh, -depth),
            SIMD3<Float>(-hw, hh, -depth)
        ]
        for c in corners {
            root.addChild(cylinder(from: origin, to: c, radius: 0.003, color: color))
        }
        // far plane edges
        for i in 0..<4 {
            root.addChild(cylinder(from: corners[i], to: corners[(i + 1) % 4], radius: 0.003, color: color))
        }
        // eye sphere
        let eye = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: color, roughness: 0.3, isMetallic: true)]
        )
        root.addChild(eye)
        return root
    }

    private static func cylinder(from: SIMD3<Float>, to: SIMD3<Float>, radius: Float, color: UIColor) -> ModelEntity {
        let delta = to - from
        let length = simd_length(delta)
        guard length > 1e-5 else {
            return ModelEntity()
        }
        let mesh = MeshResource.generateCylinder(height: length, radius: radius)
        let mat = SimpleMaterial(color: color, roughness: 0.5, isMetallic: false)
        let model = ModelEntity(mesh: mesh, materials: [mat])
        model.position = (from + to) * 0.5
        // Align Y-axis cylinder to delta
        let dir = delta / length
        let q = simd_quatf(from: SIMD3(0, 1, 0), to: dir)
        model.orientation = q
        return model
    }
}
