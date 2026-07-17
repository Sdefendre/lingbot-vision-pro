# LingBot Spatial

**Streaming 3D reconstruction for Apple Vision Pro** — an immersive spatial demo inspired by [LingBot-Map](https://github.com/Robbyant/lingbot-map) (Robbyant), the feed-forward Geometric Context Transformer for reconstructing scenes from streaming video.

Put on your Apple Vision Pro, open **LingBot Spatial**, pick a scene, hit **Play Stream**, then **Enter Immersive Space**. Geometry, camera trajectory, and keyframe frustums grow around you like a live map of the world.

| | |
|---|---|
| Platform | visionOS 2.0+ (Apple Vision Pro) |
| Stack | SwiftUI · RealityKit · Observation |
| Upstream | [Robbyant/lingbot-map](https://github.com/Robbyant/lingbot-map) (Apache-2.0) |
| This app | [Sdefendre/lingbot-spatial](https://github.com/Sdefendre/lingbot-spatial) |

---

## What you get

### Experiences
1. **Glass control window** — scene gallery, stream transport, confidence / color / rate controls  
2. **Volumetric window** — table-scale reconstruction you can walk around  
3. **Mixed immersive space** — full spatial walkthrough with pinch-drag / magnify to place & scale  

### Demo scenes (on-device, no GPU server required)
| Scene | Feel |
|---|---|
| Courthouse | Outdoor landmark, sky-masked facade |
| University | Campus-scale path |
| Loop Closure | Closed trajectory + drift correction vibe |
| Oxford Spires | Large outdoor terrain + structures |
| Indoor Walkthrough | Long corridor / room sequence |
| Aerial Survey | Bird’s-eye city-block map |

Each scene streams **poses**, **keyframes**, and **dense colored points** with confidence — the same *shape* of data LingBot-Map emits from `demo.py` / `batch_demo.py`.

### Production path
Run real LingBot-Map on a CUDA box, export points, bring them into Vision Pro:

```bash
# On your GPU machine (see upstream README)
python demo.py --model_path lingbot-map-long.pt \
  --image_folder example/courthouse --mask_sky

# Convert predictions → ASCII PLY for the headset
python scripts/export_ply_for_vision.py \
  --predictions_dir /path/to/predictions \
  --output scene.ply \
  --stride 4 \
  --conf_threshold 1.5
```

`PLYLoader` in the app reads ASCII PLY with `x y z [red green blue] [confidence]`.

---

## Run on Apple Vision Pro

### Requirements
- Mac with **Xcode 16+** and the **visionOS** SDK  
- Apple Vision Pro (device) **or** visionOS Simulator  
- Apple Developer account (free for simulator; paid for device install)  
- Your Vision Pro and Mac signed into the same Apple ID (for developer strap / wireless deploy)

### Steps
1. Clone this repo  
   ```bash
   git clone https://github.com/Sdefendre/lingbot-spatial.git
   cd lingbot-spatial
   open LingBotSpatial.xcodeproj
   ```
2. In Xcode, select the **LingBotSpatial** target → **Signing & Capabilities**  
   - Enable **Automatically manage signing**  
   - Choose your **Team**  
3. Select run destination:  
   - **Apple Vision Pro** (device), or  
   - **Apple Vision Pro (Simulator)**  
4. Press **⌘R**  
5. On device:  
   - Allow world sensing if prompted  
   - Load a scene → **Play Stream** → **Enter Immersive Space**  
   - Drag the map to reposition; pinch-magnify to scale  
   - Use the floating HUD to pause / reset / exit  

### First-run tips
- Start with **Courthouse** or **Loop Closure** — they’re the most readable in mixed immersion.  
- Raise **Confidence** if the cloud feels noisy; lower **Point size** for denser looks.  
- Open **Volume** while streaming for a desk-scale second view.  
- **Keyframes only** sparsifies the cloud for long indoor sequences.

---

## Architecture

```
LingBotSpatial/
  App/                 # @main, WindowGroup + ImmersiveSpace
  Models/              # Points, poses, scenes, settings
  Engine/
    DemoSceneGenerator # Procedural streaming frames (GCT-shaped)
    ReconstructionSession  # Observable playback / accumulation
    PLYLoader          # Real export import
  Reality/
    PointCloudEntityBuilder  # Batched colored meshes
    TrajectoryEntities       # Path + camera frustums
    ImmersiveReconstructionView
    VolumetricPreview
  Views/               # Gallery, controls, settings
```

**Stream model** (mirrors LingBot-Map concepts):
- Per-frame **camera pose** (c2w)  
- **Keyframe interval** (non-keyframes still contribute points)  
- **Confidence** filtering for visibility  
- Accumulated world point cloud with memory cap for long runs  

---

## Related repos

| Repo | Role |
|---|---|
| [Robbyant/lingbot-map](https://github.com/Robbyant/lingbot-map) | Upstream model, training, viser demo, offline renderer |
| [Sdefendre/lingbot-map](https://github.com/Sdefendre/lingbot-map) | Fork for collaboration / experiments |
| **This repo** | visionOS spatial client + demo UX |

Paper: *Geometric Context Transformer for Streaming 3D Reconstruction* — [arXiv:2604.14141](https://arxiv.org/abs/2604.14141)

---

## Collaborators

- **Steve Defendre** ([@Sdefendre](https://github.com/Sdefendre))  
- Invite issued to **[@jchacker5](https://github.com/jchacker5)** (write access on the lingbot-map fork and this app)

Accept the GitHub invitation email / notification to get write access.

---

## License

App code in this repository is provided under **Apache-2.0** (same family as upstream LingBot-Map) unless noted otherwise.  
LingBot-Map weights and third-party assets remain under their original licenses — see the [upstream LICENSE](https://github.com/Robbyant/lingbot-map/blob/main/LICENSE.txt).

---

## Honest notes (so you can ship)

1. **Full Xcode is required** on a Mac to compile and install to Vision Pro. This machine’s CLI tools alone cannot produce a device binary.  
2. **On-device inference** of the full LingBot-Map PyTorch/CUDA model is *not* included — Vision Pro doesn’t run that stack. The demo uses high-quality procedural streams that match the data model, plus a PLY bridge for real exports.  
3. **Metal mesh shaders / LowLevelMesh** can push point counts higher; the current batch mesh path prioritizes compatibility and clarity for the demo.  

Built to impress in the headset: glass UI, volumetric + immersive dual views, live trajectory, keyframe frustums, and a stream that *feels* like watching LingBot-Map think in 3D.
