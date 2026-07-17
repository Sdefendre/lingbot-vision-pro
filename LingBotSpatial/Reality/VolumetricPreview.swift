import SwiftUI
import RealityKit
import simd
import UIKit

/// Volumetric window: table-scale reconstruction you can walk around.
struct VolumetricPreview: View {
    @Environment(ReconstructionSession.self) private var session

    var body: some View {
        ZStack(alignment: .bottom) {
            RealityView { content in
                let root = Entity()
                root.name = "VolumeRoot"

                let cloud = PointCloudEntityBuilder.makeRoot()
                cloud.name = "PointCloudRoot"
                let traj = TrajectoryEntities.makeRoot()
                traj.name = "TrajectoryRoot"
                root.addChild(cloud)
                root.addChild(traj)

                let platform = ModelEntity(
                    mesh: .generateCylinder(height: 0.01, radius: 0.35),
                    materials: [
                        SimpleMaterial(
                            color: UIColor(white: 0.2, alpha: 0.35),
                            roughness: 1.0,
                            isMetallic: false
                        )
                    ]
                )
                platform.name = "Platform"
                platform.position.y = -0.18
                root.addChild(platform)

                content.add(root)
            } update: { content in
                guard let root = content.entities.first(where: { $0.name == "VolumeRoot" }),
                      let cloud = root.findEntity(named: "PointCloudRoot"),
                      let traj = root.findEntity(named: "TrajectoryRoot") else { return }

                let extent = session.boundsExtent
                let maxDim = max(extent.x, max(extent.y, max(extent.z, 0.3)))
                let s = 0.45 / maxDim
                cloud.scale = SIMD3<Float>(repeating: s)
                traj.scale = SIMD3<Float>(repeating: s)
                cloud.position = -session.boundsCenter * s
                traj.position = -session.boundsCenter * s

                PointCloudEntityBuilder.rebuildColorBucketed(
                    root: cloud,
                    points: session.filteredPoints(limit: 25_000),
                    pointScale: session.settings.pointScale * 2.2
                )

                if session.settings.showTrajectory {
                    traj.isEnabled = true
                    TrajectoryEntities.rebuild(
                        root: traj,
                        poses: session.poses,
                        keyframes: session.keyframePoses,
                        showFrustums: session.settings.showFrustums
                    )
                } else {
                    traj.isEnabled = false
                }
            }

            HStack {
                Image(systemName: session.selectedScene.systemImage)
                    .foregroundStyle(session.selectedScene.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.selectedScene.title)
                        .font(.headline)
                    Text(session.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Int(session.progress * 100))%")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(session.selectedScene.accent)
            }
            .padding()
            .glassBackgroundEffect()
            .padding()
        }
    }
}
