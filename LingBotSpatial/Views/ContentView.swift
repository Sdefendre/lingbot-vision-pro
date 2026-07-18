import SwiftUI

struct ContentView: View {
    @Environment(ReconstructionSession.self) private var session
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var session = session

        NavigationSplitView {
            SceneGalleryView(selection: $session.selectedScene)
                .navigationTitle("Scenes")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HeroHeader()
                    SceneDetailCard()
                    StreamControlsCard()
                    SettingsCard()
                    SpatialActionsCard(
                        openImmersive: openImmersive,
                        closeImmersive: closeImmersive,
                        openVolume: {
                            openWindow(id: "volume")
                            session.isVolumeOpen = true
                        }
                    )
                    TechFooter()
                }
                .padding(28)
            }
            .background(backgroundGradient)
        }
        .environment(session)
        .onChange(of: session.selectedScene) { _, new in
            session.selectScene(new)
            Task { await session.loadSelectedScene() }
        }
        .task {
            if session.frames.isEmpty {
                await session.loadSelectedScene()
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.07, blue: 0.12),
                Color(red: 0.08, green: 0.10, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func openImmersive() {
        Task {
            switch await openImmersiveSpace(id: "reconstruction") {
            case .opened:
                session.isImmersiveOpen = true
            case .userCancelled, .error:
                session.isImmersiveOpen = false
            @unknown default:
                session.isImmersiveOpen = false
            }
        }
    }

    private func closeImmersive() {
        Task {
            await dismissImmersiveSpace()
            session.isImmersiveOpen = false
        }
    }
}

// MARK: - Hero

private struct HeroHeader: View {
    @Environment(ReconstructionSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(session.selectedScene.accent.gradient)
                        .frame(width: 52, height: 52)
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("LingBot Spatial")
                        .font(.largeTitle.weight(.bold))
                    Text("Streaming 3D reconstruction on Apple Vision Pro")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Experience LingBot-Map’s feed-forward Geometric Context Transformer as a spatial walkthrough — poses, keyframes, and dense geometry stream into your room in real time.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Scene detail

private struct SceneDetailCard: View {
    @Environment(ReconstructionSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(session.selectedScene.title, systemImage: session.selectedScene.systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(session.selectedScene.accent)

            Text(session.selectedScene.blurb)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                metric("Frames", "\(session.selectedScene.frameCount)")
                metric("Keyframe Δ", "\(session.selectedScene.keyframeInterval)")
                metric("Sky mask", session.selectedScene.maskSky ? "On" : "Off")
                metric("Status", statusLabel)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackgroundEffect()
    }

    private var statusLabel: String {
        switch session.playback {
        case .idle: return "Idle"
        case .loading: return "Loading"
        case .ready: return "Ready"
        case .streaming: return "Live"
        case .paused: return "Paused"
        case .completed: return "Done"
        case .failed: return "Error"
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stream controls

private struct StreamControlsCard: View {
    @Environment(ReconstructionSession.self) private var session

    var body: some View {
        @Bindable var session = session

        VStack(alignment: .leading, spacing: 16) {
            Text("Stream")
                .font(.title3.weight(.semibold))

            ProgressView(value: session.progress) {
                Text(session.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } currentValueLabel: {
                Text("\(session.currentFrameIndex + 1) / \(max(session.frames.count, 1))")
                    .font(.caption.monospacedDigit())
            }
            .tint(session.selectedScene.accent)

            Slider(value: Binding(
                get: { session.progress },
                set: { session.seek(to: $0) }
            ), in: 0...1)
            .disabled(session.frames.isEmpty)

            HStack(spacing: 12) {
                Button {
                    Task { await session.loadSelectedScene() }
                } label: {
                    Label("Load", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    session.togglePlayPause()
                } label: {
                    Label(session.isPlaying ? "Pause" : "Play Stream",
                          systemImage: session.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(session.selectedScene.accent)
                .controlSize(.large)

                Button {
                    session.stepForward()
                } label: {
                    Label("Step", systemImage: "forward.frame")
                }
                .buttonStyle(.bordered)

                Button {
                    session.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Label("\(session.totalPointCount.formatted()) points", systemImage: "circle.grid.3x3.fill")
                Spacer()
                Label(String(format: "%.1f FPS", session.streamFPSActual), systemImage: "gauge.with.dots.needle.67percent")
                Spacer()
                Label("\(session.poses.count) poses", systemImage: "camera.viewfinder")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .glassBackgroundEffect()
    }
}

// MARK: - Settings

private struct SettingsCard: View {
    @Environment(ReconstructionSession.self) private var session

    var body: some View {
        @Bindable var session = session

        VStack(alignment: .leading, spacing: 16) {
            Text("Visualization")
                .font(.title3.weight(.semibold))

            LabeledContent("Confidence") {
                Slider(value: $session.settings.confidenceThreshold, in: 0...1)
                    .frame(maxWidth: 260)
            }

            LabeledContent("Point size") {
                Slider(value: $session.settings.pointScale, in: 0.004...0.04)
                    .frame(maxWidth: 260)
            }

            LabeledContent("Stream rate") {
                Slider(value: $session.settings.streamFPS, in: 4...30, step: 1)
                    .frame(maxWidth: 260)
            }

            Picker("Color mode", selection: $session.settings.colorMode) {
                ForEach(PointColorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Show trajectory", isOn: $session.settings.showTrajectory)
            Toggle("Show camera frustums", isOn: $session.settings.showFrustums)
            Toggle("Keyframes only (points)", isOn: $session.settings.showKeyframesOnly)
        }
        .padding(20)
        .glassBackgroundEffect()
    }
}

// MARK: - Spatial actions

private struct SpatialActionsCard: View {
    @Environment(ReconstructionSession.self) private var session
    var openImmersive: () -> Void
    var closeImmersive: () -> Void
    var openVolume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Spatial Experiences")
                .font(.title3.weight(.semibold))

            Text("Open a volumetric window on your table, or step into a mixed immersive reconstruction that streams around you.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Button(action: openVolume) {
                    Label("Open Volume", systemImage: "cube.transparent")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if session.isImmersiveOpen {
                    Button(action: closeImmersive) {
                        Label("Exit Immersive", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                } else {
                    Button(action: openImmersive) {
                        Label("Enter Immersive Space", systemImage: "vision.pro")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(session.selectedScene.accent)
                    .controlSize(.large)
                }
            }
        }
        .padding(20)
        .glassBackgroundEffect()
    }
}

// MARK: - Footer

private struct TechFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Technology")
                .font(.headline)
            Text("Inspired by LingBot-Map (Robbyant) — Geometric Context Transformer for streaming 3D reconstruction. Demo scenes synthesize poses + dense colored points on-device so you can experience the full spatial UX without a CUDA GPU. Drop real PLY exports from the Python pipeline into the app for production data.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link("github.com/Robbyant/lingbot-map", destination: URL(string: "https://github.com/Robbyant/lingbot-map")!)
                .font(.footnote)
            Link("github.com/Sdefendre/lingbot-vision-pro", destination: URL(string: "https://github.com/Sdefendre/lingbot-vision-pro")!)
                .font(.footnote)
        }
        .padding(.top, 8)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(ReconstructionSession())
}
