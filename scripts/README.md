# Scripts

## `export_ply_for_vision.py`

Convert LingBot-Map-style prediction dumps into an **ASCII PLY** that `PLYLoader` in the visionOS app understands.

### Dependencies

```bash
pip install numpy
```

### Examples

```bash
# Folder of per-frame .npz / .npy predictions
python scripts/export_ply_for_vision.py \
  --predictions_dir /path/to/predictions \
  --output scene.ply \
  --stride 4 \
  --conf_threshold 1.5 \
  --max_points 200000

# Single Nx3 or Nx6 float array
python scripts/export_ply_for_vision.py \
  --xyzrgb points.npy \
  --output scene.ply
```

### Output schema

ASCII PLY vertices:

| property | type | notes |
|---|---|---|
| x y z | float | world position |
| red green blue | uchar | 0–255 |
| confidence | float | higher = more reliable |

### Keys probed in NPZ files

- Points: `points`, `world_points`, `pts3d`, `xyz`, `arr`  
- Colors: `colors`, `point_colors`, `rgb`, `images`  
- Confidence: `conf`, `confidence`, `point_conf`  

Upstream model I/O can change; if a dump fails, inspect keys and extend `_first_key` lists accordingly.
