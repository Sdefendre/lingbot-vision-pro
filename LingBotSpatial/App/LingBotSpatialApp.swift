import SwiftUI

/// LingBot Spatial — Immersive streaming 3D reconstruction for Apple Vision Pro.
/// Powered by concepts from LingBot-Map (Robbyant): Geometric Context Transformer
/// for feed-forward streaming scene reconstruction.
@main
struct LingBotSpatialApp: App {
    @State private var session = ReconstructionSession()

    var body: some Scene {
        // Primary glass control window
        WindowGroup(id: "main") {
            ContentView()
                .environment(session)
        }
        .defaultSize(width: 920, height: 680)
        .windowResizability(.contentSize)

        // Volumetric 3D preview of the growing reconstruction
        WindowGroup(id: "volume") {
            VolumetricPreview()
                .environment(session)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.7, height: 0.55, depth: 0.7, in: .meters)

        // Full mixed / progressive immersion for walk-through
        ImmersiveSpace(id: "reconstruction") {
            ImmersiveReconstructionView()
                .environment(session)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed, .progressive, .full)
    }
}
