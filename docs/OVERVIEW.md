# LingBot Spatial — technical overview

Portfolio-oriented notes for reviewers, collaborators, and future you.

## Product summary

**LingBot Spatial** is a visionOS 2 app that presents streaming 3D reconstruction as a spatial experience on Apple Vision Pro. It is inspired by Robbyant’s [LingBot-Map](https://github.com/Robbyant/lingbot-map) (Geometric Context Transformer) and ships as the public repo [lingbot-vision-pro](https://github.com/Sdefendre/lingbot-vision-pro).

| Layer | What ships |
|---|---|
| UX | Glass control window, volumetric table preview, mixed immersive space + HUD |
| Data (demo) | Six procedural scenes generating poses + confidence-colored points |
| Data (real) | Python PLY export from LingBot-Map predictions + `PLYLoader` |
| Render | RealityKit batched point markers, trajectory path, keyframe frustums |

## Design goals

1. **Headset-first storytelling** — show what streaming reconstruction feels like in the room, not only on a desktop visualizer.  
2. **Honest demo boundary** — no fake claim of full CUDA/PyTorch inference on-device.  
3. **Same data contract as research code** — frames carry pose, keyframe flag, points, confidence.  
4. **Dual viewing scales** — desk volume for inspection; immersive for presence.  

## Runtime flow

```text
User selects DemoSceneKind
        │
        ▼
DemoSceneGenerator.generate  →  [StreamFrame]
        │
        ▼
ReconstructionSession.load / play
  · accumulate points (cap ~120k)
  · track poses + keyframes
  · apply confidence / color / keyframe filters
        │
        ├─► ContentView (controls)
        ├─► VolumetricPreview (≤ ~25k pts)
        └─► ImmersiveReconstructionView (≤ ~40k pts, drag + magnify)
```

## Key types

| Type | Role |
|---|---|
| `ReconPoint` | `position`, `color` (RGB 0…1), `confidence` |
| `CameraPose` | frame index, position, quaternion, keyframe flag |
| `StreamFrame` | one streaming step: pose + points + timestamp |
| `DemoSceneKind` | six curated procedural scenarios |
| `ReconstructionSettings` | confidence, point scale, FPS, color mode, toggles |
| `ReconstructionSession` | `@Observable` session brain (`@MainActor`) |

## RealityKit strategy

- Points are **not** raw GPU point primitives; they are **batched colored box meshes** (`PointCloudEntityBuilder`) for broad visionOS compatibility and stable frame times.  
- Trajectory and frustums are separate entity trees (`TrajectoryEntities`) so they can be toggled without rebuilding the cloud.  
- Immersive root is placed ~2 m in front of the user; auto fit-to-bounds scale is multiplied by user pinch scale; drag applies a user offset.  

## Export bridge

`scripts/export_ply_for_vision.py`:

- Inputs: directory of `.npz` / `.npy` predictions, or a single `N×3` / `N×6` xyzrgb array  
- Filters: stride, confidence threshold, max points  
- Output: ASCII PLY with `x y z red green blue confidence`  

`PLYLoader` parses that ASCII layout in Swift. There is intentionally **no** shipping document-picker UI yet; the loader is the integration hook for Resources bundles or a future import feature.

## What this is not

- Not an App Store product listing (demo / portfolio build).  
- Not on-device LingBot-Map weights or training code.  
- Not a full SLAM stack with live headset camera fusion (world sensing is used for placement context; geometry comes from the stream / PLY path).  

## Citation (upstream)

If you reference the research model:

- Paper: [arXiv:2604.14141](https://arxiv.org/abs/2604.14141) — *Geometric Context Transformer for Streaming 3D Reconstruction*  
- Code: https://github.com/Robbyant/lingbot-map  

## Ownership

- **Author:** Steve Defendre ([@Sdefendre](https://github.com/Sdefendre))  
- **Studio:** [Defendre Solutions](https://www.defendresolutions.com)  
- **Case study:** https://www.defendresolutions.com/projects/lingbot-vision-pro  
- **License:** Apache-2.0 (this repository’s app code)
