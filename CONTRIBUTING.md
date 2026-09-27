# Contributing

Thanks for interest in **LingBot Spatial** (`lingbot-vision-pro`).

## Ground rules

- Keep the demo **honest**: do not document on-device CUDA/PyTorch inference that is not implemented.  
- Prefer small, focused PRs (one feature or fix).  
- Match existing Swift style: clear names, short comments on non-obvious spatial math, `@MainActor` for UI/session types.  
- Do not commit secrets, provisioning profiles, `.p12`, or large binary datasets (`.ply` / `.npz` are gitignored).  

## Dev setup

1. macOS + Xcode 16+ with visionOS 2 SDK  
2. `open LingBotSpatial.xcodeproj`  
3. Set your development team under Signing  
4. Run on **Apple Vision Pro** or the **visionOS Simulator**  

Python export helper (optional):

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install numpy
python scripts/export_ply_for_vision.py --help
```

## Geometry and export regression checks

These run on macOS with Command Line Tools and Python/NumPy; they do not replace
a visionOS Simulator build:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash scripts/test_geometry.sh
```

## Suggested contribution areas

- Document picker / share-sheet import wired to `PLYLoader`  
- Higher-density point rendering (`LowLevelMesh` / metal paths) with a quality fallback  
- Live immersion style picker (mixed / progressive / full) bound to `ImmersionMode`  
- Additional demo scenes that stay readable in mixed immersion  

## PR checklist

- [ ] Builds for visionOS Simulator (and device if you have one)  
- [ ] README / `docs/OVERVIEW.md` updated if behavior or claims changed  
- [ ] No invented performance metrics in docs  
- [ ] Apache-2.0 compatible dependencies only  

## Questions

Open a GitHub issue on [Sdefendre/lingbot-vision-pro](https://github.com/Sdefendre/lingbot-vision-pro).
