import SwiftUI

struct SceneGalleryView: View {
    @Binding var selection: DemoSceneKind
    @Environment(ReconstructionSession.self) private var session

    var body: some View {
        List(DemoSceneKind.allCases, selection: $selection) { scene in
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(scene.accent.opacity(0.22))
                        .frame(width: 44, height: 44)
                    Image(systemName: scene.systemImage)
                        .foregroundStyle(scene.accent)
                        .font(.title3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(scene.title)
                        .font(.headline)
                    Text(scene.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .tag(scene)
            .padding(.vertical, 4)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selection == scene ? scene.accent.opacity(0.12) : Color.clear)
                    .padding(2)
            )
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LingBot-Map")
                    .font(.caption.weight(.semibold))
                Text("Streaming · ~20 FPS class · GCT")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial)
        }
    }
}
