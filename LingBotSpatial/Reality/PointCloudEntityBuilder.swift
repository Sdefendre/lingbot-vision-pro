import Foundation
import RealityKit
import simd
import UIKit

/// Builds / updates RealityKit entities that represent a streaming point cloud.
/// Uses batched colored box instances for broad visionOS compatibility and solid FPS.
@MainActor
enum PointCloudEntityBuilder {
    private static let maxRenderPoints = 45_000
    private static let batchSize = 2_500

    /// Root entity containing child batches named `pc_batch_*`.
    static func makeRoot() -> Entity {
        let root = Entity()
        root.name = "PointCloudRoot"
        return root
    }

    /// Rebuild the entire point cloud mesh under `root`.
    static func rebuild(root: Entity, points: [ReconPoint], pointScale: Float) {
        // Clear old batches
        for child in root.children.filter({ $0.name.hasPrefix("pc_batch_") }) {
            child.removeFromParent()
        }

        guard !points.isEmpty else { return }

        let stride: Int = max(points.count / maxRenderPoints, 1)
        var sampled: [ReconPoint] = []
        sampled.reserveCapacity(min(points.count, maxRenderPoints))
        var i = 0
        while i < points.count && sampled.count < maxRenderPoints {
            sampled.append(points[i])
            i += stride
        }

        let scale = max(pointScale, 0.004)
        var batchIndex = 0
        var cursor = 0
        while cursor < sampled.count {
            let end = min(cursor + batchSize, sampled.count)
            let slice = Array(sampled[cursor..<end])
            if let entity = makeBatchEntity(points: slice, scale: scale, name: "pc_batch_\(batchIndex)") {
                root.addChild(entity)
            }
            batchIndex += 1
            cursor = end
        }
    }

    /// Incremental append for streaming: only add a new batch for `newPoints`.
    static func append(root: Entity, newPoints: [ReconPoint], pointScale: Float, totalCap: Int = maxRenderPoints) {
        guard !newPoints.isEmpty else { return }
        let existing = root.children.filter { $0.name.hasPrefix("pc_batch_") }.count
        // If already dense, full rebuild sparsified
        if existing * batchSize > totalCap {
            return
        }
        let scale = max(pointScale, 0.004)
        let name = "pc_batch_\(existing)_\(UUID().uuidString.prefix(4))"
        if let entity = makeBatchEntity(points: Array(newPoints.prefix(batchSize)), scale: scale, name: name) {
            root.addChild(entity)
        }
    }

    // MARK: - Mesh construction

    private static func makeBatchEntity(points: [ReconPoint], scale: Float, name: String) -> ModelEntity? {
        guard !points.isEmpty else { return nil }

        // One combined mesh: each point → cube (12 tris). For demo density this is fine.
        // To keep generation fast, use a low-poly box descriptor per point via MeshResource async is heavy;
        // we synthesize a single MeshDescriptor.

        let vertsPerCube = 8
        let trisPerCube = 12
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(points.count * vertsPerCube)
        normals.reserveCapacity(points.count * vertsPerCube)
        colors.reserveCapacity(points.count * vertsPerCube)
        indices.reserveCapacity(points.count * trisPerCube * 3)

        let h = scale * 0.5
        let cornerOffsets: [SIMD3<Float>] = [
            SIMD3(-h, -h, -h), SIMD3(h, -h, -h), SIMD3(h, h, -h), SIMD3(-h, h, -h),
            SIMD3(-h, -h, h), SIMD3(h, -h, h), SIMD3(h, h, h), SIMD3(-h, h, h)
        ]
        // Faces as triangles (two per face)
        let faces: [[Int]] = [
            [0, 1, 2, 0, 2, 3], // -Z
            [5, 4, 7, 5, 7, 6], // +Z
            [4, 0, 3, 4, 3, 7], // -X
            [1, 5, 6, 1, 6, 2], // +X
            [3, 2, 6, 3, 6, 7], // +Y
            [4, 5, 1, 4, 1, 0]  // -Y
        ]
        let faceNormals: [SIMD3<Float>] = [
            SIMD3(0, 0, -1), SIMD3(0, 0, 1),
            SIMD3(-1, 0, 0), SIMD3(1, 0, 0),
            SIMD3(0, 1, 0), SIMD3(0, -1, 0)
        ]

        for p in points {
            let base = UInt32(positions.count)
            let c = SIMD4<Float>(p.color.x, p.color.y, p.color.z, 1)
            // Expand to 24 verts (unique normal per face corner) for clean lighting
            for f in 0..<6 {
                let face = faces[f]
                let n = faceNormals[f]
                let vStart = UInt32(positions.count)
                // 4 unique corners referenced by face (0,1,2,3 of face pair uses 0,1,2 and 0,2,3)
                let cornerIdx = [face[0], face[1], face[2], face[5]]
                // simpler: emit 6 verts per face (two tris)
                for k in 0..<6 {
                    let ci = face[k]
                    positions.append(p.position + cornerOffsets[ci])
                    normals.append(n)
                    colors.append(c)
                }
                indices.append(contentsOf: [
                    vStart, vStart + 1, vStart + 2,
                    vStart + 3, vStart + 4, vStart + 5
                ])
            }
            _ = base
        }

        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)

        // Vertex colors via material — RealityKit SimpleMaterial is uniform;
        // use per-point average color for batch tint (good enough + fast).
        // For true per-vertex color we'd need shader graph / LowLevelMesh.
        // Instead split by quantized color buckets for nicer look when few colors.

        do {
            let mesh = try MeshResource.generate(from: [descriptor])
            let avg = averageColor(points)
            var material = SimpleMaterial()
            material.color = .init(tint: UIColor(
                red: CGFloat(avg.x),
                green: CGFloat(avg.y),
                blue: CGFloat(avg.z),
                alpha: 1
            ))
            material.roughness = 0.85
            material.metallic = 0.05
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.name = name
            model.components.set(InputTargetComponent())
            model.generateCollisionShapes(recursive: false)
            return model
        } catch {
            return nil
        }
    }

    /// Better quality path: group points into color buckets and make one mesh each.
    static func rebuildColorBucketed(root: Entity, points: [ReconPoint], pointScale: Float) {
        for child in root.children.filter({ $0.name.hasPrefix("pc_batch_") }) {
            child.removeFromParent()
        }
        guard !points.isEmpty else { return }

        let stride = max(points.count / maxRenderPoints, 1)
        var buckets: [UInt32: [ReconPoint]] = [:]
        var i = 0
        var count = 0
        while i < points.count && count < maxRenderPoints {
            let p = points[i]
            let key = quantizeColor(p.color)
            buckets[key, default: []].append(p)
            count += 1
            i += stride
        }

        var b = 0
        for (_, group) in buckets {
            // Split large buckets
            var start = 0
            while start < group.count {
                let end = min(start + batchSize, group.count)
                let slice = Array(group[start..<end])
                if let entity = makeBatchEntity(points: slice, scale: max(pointScale, 0.004), name: "pc_batch_\(b)") {
                    // Override material to exact bucket color
                    if let first = slice.first {
                        var mat = SimpleMaterial(
                            color: UIColor(
                                red: CGFloat(first.color.x),
                                green: CGFloat(first.color.y),
                                blue: CGFloat(first.color.z),
                                alpha: 1
                            ),
                            roughness: 0.8,
                            isMetallic: false
                        )
                        entity.model?.materials = [mat]
                    }
                    root.addChild(entity)
                }
                b += 1
                start = end
            }
        }
    }

    private static func quantizeColor(_ c: SIMD3<Float>) -> UInt32 {
        let r = UInt32(min(max(c.x, 0), 1) * 15)
        let g = UInt32(min(max(c.y, 0), 1) * 15)
        let b = UInt32(min(max(c.z, 0), 1) * 15)
        return (r << 8) | (g << 4) | b
    }

    private static func averageColor(_ points: [ReconPoint]) -> SIMD3<Float> {
        var acc = SIMD3<Float>(repeating: 0)
        for p in points { acc += p.color }
        let n = Float(max(points.count, 1))
        return acc / n
    }
}
