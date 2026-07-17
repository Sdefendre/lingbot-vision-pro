#!/usr/bin/env python3
"""
Convert LingBot-Map demo outputs into an ASCII PLY for LingBot Spatial (visionOS).

Usage examples:

  # From a folder of per-frame prediction NPZs (batch_demo --save_predictions)
  python scripts/export_ply_for_vision.py \
      --predictions_dir /path/to/outputs/indoor_travel/predictions \
      --output scene.ply \
      --stride 4 \
      --conf_threshold 1.5

  # From a simple N×6 float32 binary dump (xyzrgb)
  python scripts/export_ply_for_vision.py --xyzrgb points.npy --output scene.ply

Notes:
  - LingBot-Map prediction tensors vary by version; this script tries common keys:
    points / world_points / pts3d, colors / point_colors / images, conf / confidence.
  - For the full interactive stream on Vision Pro, keep using the on-device demo scenes;
    this export is for bringing *real* reconstructed geometry into the volume/immersive views.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys
from typing import Optional, Tuple

import numpy as np


def _first_key(d: dict, names: Tuple[str, ...]):
    for n in names:
        if n in d:
            return d[n]
    return None


def load_npz(path: str) -> Tuple[np.ndarray, Optional[np.ndarray], Optional[np.ndarray]]:
    data = np.load(path, allow_pickle=True)
    # npz or npy
    if hasattr(data, "files"):
        mapping = {k: data[k] for k in data.files}
    else:
        mapping = {"arr": np.asarray(data)}

    pts = _first_key(mapping, ("points", "world_points", "pts3d", "xyz", "arr"))
    if pts is None:
        raise ValueError(f"No point array in {path}; keys={list(mapping.keys())}")

    pts = np.asarray(pts, dtype=np.float32).reshape(-1, 3)

    cols = _first_key(mapping, ("colors", "point_colors", "rgb", "images"))
    if cols is not None:
        cols = np.asarray(cols, dtype=np.float32).reshape(-1, -1)
        if cols.shape[-1] > 3:
            cols = cols[..., :3]
        cols = cols.reshape(-1, 3)
        if cols.max() > 1.5:
            cols = cols / 255.0
        if cols.shape[0] != pts.shape[0]:
            # broadcast or trim
            n = min(cols.shape[0], pts.shape[0])
            pts = pts[:n]
            cols = cols[:n]
    else:
        cols = None

    conf = _first_key(mapping, ("conf", "confidence", "point_conf"))
    if conf is not None:
        conf = np.asarray(conf, dtype=np.float32).reshape(-1)
        n = min(conf.shape[0], pts.shape[0])
        pts = pts[:n]
        conf = conf[:n]
        if cols is not None:
            cols = cols[:n]
    return pts, cols, conf


def write_ply(path: str, pts: np.ndarray, cols: Optional[np.ndarray], conf: Optional[np.ndarray]):
    n = pts.shape[0]
    if cols is None:
        cols = np.full((n, 3), 0.7, dtype=np.float32)
    if conf is None:
        conf = np.full((n,), 0.8, dtype=np.float32)

    cols_u8 = np.clip(cols * 255.0, 0, 255).astype(np.uint8)

    with open(path, "w", encoding="utf-8") as f:
        f.write("ply\nformat ascii 1.0\n")
        f.write(f"element vertex {n}\n")
        f.write("property float x\nproperty float y\nproperty float z\n")
        f.write("property uchar red\nproperty uchar green\nproperty uchar blue\n")
        f.write("property float confidence\nend_header\n")
        for i in range(n):
            x, y, z = pts[i]
            r, g, b = cols_u8[i]
            c = float(conf[i])
            f.write(f"{x:.6f} {y:.6f} {z:.6f} {r} {g} {b} {c:.4f}\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--predictions_dir", type=str, default=None, help="Directory of .npz frames")
    ap.add_argument("--xyzrgb", type=str, default=None, help="Single .npy with Nx3 or Nx6")
    ap.add_argument("--output", type=str, required=True)
    ap.add_argument("--stride", type=int, default=1)
    ap.add_argument("--conf_threshold", type=float, default=0.0)
    ap.add_argument("--max_points", type=int, default=200_000)
    args = ap.parse_args()

    all_pts = []
    all_cols = []
    all_conf = []

    if args.xyzrgb:
        arr = np.load(args.xyzrgb)
        arr = np.asarray(arr, dtype=np.float32)
        if arr.ndim != 2 or arr.shape[1] < 3:
            sys.exit("xyzrgb array must be N×3 or N×6+")
        pts = arr[:, :3]
        cols = arr[:, 3:6] if arr.shape[1] >= 6 else None
        conf = None
        all_pts.append(pts)
        all_cols.append(cols)
        all_conf.append(conf)
    elif args.predictions_dir:
        paths = sorted(glob.glob(os.path.join(args.predictions_dir, "**", "*.npz"), recursive=True))
        paths += sorted(glob.glob(os.path.join(args.predictions_dir, "*.npy")))
        if not paths:
            sys.exit(f"No npz/npy under {args.predictions_dir}")
        for p in paths[:: max(args.stride, 1)]:
            try:
                pts, cols, conf = load_npz(p)
            except Exception as e:
                print(f"skip {p}: {e}", file=sys.stderr)
                continue
            all_pts.append(pts)
            all_cols.append(cols)
            all_conf.append(conf)
            print(f"loaded {p}: {len(pts)} pts")
    else:
        sys.exit("Provide --predictions_dir or --xyzrgb")

    pts = np.concatenate(all_pts, axis=0)
    # colors
    if any(c is not None for c in all_cols):
        cols_list = []
        for c, p in zip(all_cols, all_pts):
            if c is None:
                cols_list.append(np.full((len(p), 3), 0.7, dtype=np.float32))
            else:
                cols_list.append(c)
        cols = np.concatenate(cols_list, axis=0)
    else:
        cols = None

    if any(c is not None for c in all_conf):
        conf_list = []
        for c, p in zip(all_conf, all_pts):
            if c is None:
                conf_list.append(np.full((len(p),), 0.8, dtype=np.float32))
            else:
                conf_list.append(c)
        conf = np.concatenate(conf_list, axis=0)
    else:
        conf = None

    if conf is not None and args.conf_threshold > 0:
        mask = conf >= args.conf_threshold
        pts = pts[mask]
        if cols is not None:
            cols = cols[mask]
        conf = conf[mask]

    if len(pts) > args.max_points:
        idx = np.linspace(0, len(pts) - 1, args.max_points).astype(np.int64)
        pts = pts[idx]
        if cols is not None:
            cols = cols[idx]
        if conf is not None:
            conf = conf[idx]

    os.makedirs(os.path.dirname(os.path.abspath(args.output)) or ".", exist_ok=True)
    write_ply(args.output, pts, cols, conf)
    print(f"Wrote {len(pts)} points → {args.output}")


if __name__ == "__main__":
    main()
