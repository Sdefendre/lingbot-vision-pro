import SwiftUI
import RealityKit
import simd
import UIKit

/// Mixed-reality immersive space: reconstruction grows in the room around you.
struct ImmersiveReconstructionView: View {
    @Environment(ReconstructionSession.self) private var session

    /// User placement offset applied on top of the default stand-in pose.
    @State private var userOffset = SIMD3<Float>(0, 0, 0)
    /// Extra uniform scale from pinch-magnify (1 = fit-to-bounds only).
    @State private var userScale: Float = 1
    @State private var dragStartOffset: SIMD3<Float>?
    @State private var magnifyStartScale: Float?

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            root.name = "ImmersiveRoot"
            // Place scene ~2m in front of user, chest height
            root.position = SIMD3<Float>(0, 0.95, -2.2)
            root.scale = SIMD3<Float>(repeating: 0.28)

            let cloud = PointCloudEntityBuilder.makeRoot()
            cloud.name = "PointCloudRoot"
            let traj = TrajectoryEntities.makeRoot()
            traj.name = "TrajectoryRoot"
            let ground = makeGroundRing()

            root.addChild(cloud)
            root.addChild(traj)
            root.addChild(ground)
            content.add(root)

            if let hud = attachments.entity(for: "hud") {
                hud.position = SIMD3<Float>(0, 1.55, -1.15)
                content.add(hud)
            }
        } update: { content, _ in
            guard let root = content.entities.first(where: { $0.name == "ImmersiveRoot" }),
                  let cloud = root.findEntity(named: "PointCloudRoot"),
                  let traj = root.findEntity(named: "TrajectoryRoot") else { return }

            // Fit scene into ~2.2 m box, then apply user pinch scale
            let extent = session.boundsExtent
            let maxDim = max(extent.x, max(extent.y, max(extent.z, 0.5)))
            let fit = 2.2 / maxDim
            let s = min(max(fit * userScale, 0.05), 2.5)
            root.scale = SIMD3<Float>(repeating: s)
            root.position = SIMD3<Float>(0, 0.95, -2.2) + userOffset

            let center = session.boundsCenter
            cloud.position = -center
            traj.position = -center

            let points = session.filteredPoints(limit: 40_000)
            PointCloudEntityBuilder.rebuildColorBucketed(
                root: cloud,
                points: points,
                pointScale: session.settings.pointScale * 1.4
            )

            traj.isEnabled = session.settings.showTrajectory
            if session.settings.showTrajectory {
                TrajectoryEntities.rebuild(
                    root: traj,
                    poses: session.poses,
                    keyframes: session.keyframePoses,
                    showFrustums: session.settings.showFrustums
                )
            }
        } attachments: {
            Attachment(id: "hud") {
                ImmersiveHUD()
                    .environment(session)
            }
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    if dragStartOffset == nil {
                        dragStartOffset = userOffset
                    }
                    guard let start = dragStartOffset else { return }
                    let t = value.translation
                    // Map 2D drag to gentle X / Y placement in meters
                    userOffset = start + SIMD3<Float>(
                        Float(t.width) * 0.0015,
                        Float(-t.height) * 0.0015,
                        0
                    )
                }
                .onEnded { _ in
                    dragStartOffset = nil
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if magnifyStartScale == nil {
                        magnifyStartScale = userScale
                    }
                    guard let start = magnifyStartScale else { return }
                    userScale = min(max(start * Float(value.magnification), 0.25), 4)
                }
                .onEnded { _ in
                    magnifyStartScale = nil
                }
        )
    }

    private func makeGroundRing() -> Entity {
        let ent = Entity()
        ent.name = "GroundRing"
        let mesh = MeshResource.generateCylinder(height: 0.005, radius: 1.2)
        let mat = SimpleMaterial(
            color: UIColor(white: 1, alpha: 0.08),
            roughness: 1.0,
            isMetallic: false
        )
        let model = ModelEntity(mesh: mesh, materials: [mat])
        model.position = SIMD3<Float>(0, -0.02, 0)
        ent.addChild(model)
        return ent
    }
}

// MARK: - In-space HUD

struct ImmersiveHUD: View {
    @Environment(ReconstructionSession.self) private var session
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(session.selectedScene.accent)
                Text("LingBot Spatial")
                    .font(.headline)
                Spacer()
                Text(session.selectedScene.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: session.progress)
                .tint(session.selectedScene.accent)

            HStack {
                Text("Frame \(session.currentFrameIndex + 1)/\(max(session.frames.count, 1))")
                    .font(.caption.monospacedDigit())
                Spacer()
                Text("\(session.totalPointCount.formatted()) pts")
                    .font(.caption.monospacedDigit())
                Spacer()
                Text(String(format: "%.0f FPS", session.streamFPSActual))
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Button {
                    session.togglePlayPause()
                } label: {
                    Label(
                        session.isPlaying ? "Pause" : "Play",
                        systemImage: session.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(session.selectedScene.accent)

                Button {
                    session.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await dismissImmersiveSpace() }
                } label: {
                    Label("Exit", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(width: 420)
        .glassBackgroundEffect()
    }
}
