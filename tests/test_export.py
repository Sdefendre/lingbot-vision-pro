import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/export_ply_for_vision.py"


class ExportTests(unittest.TestCase):
    def run_export(self, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *map(str, args)],
            capture_output=True,
            text=True,
        )

    def test_colored_prediction_preserves_positions_colors_and_confidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            np.savez(
                root / "frame.npz",
                points=[[1, 2, 3], [4, 5, 6]],
                colors=[[255, 0, 0], [0, 128, 255]],
                conf=[0.25, 0.75],
            )
            output = root / "scene.ply"
            result = self.run_export("--predictions_dir", root, "--output", output)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                output.read_text().split("end_header\n")[1].splitlines(),
                [
                    "1.000000 2.000000 3.000000 255 0 0 0.2500",
                    "4.000000 5.000000 6.000000 0 128 255 0.7500",
                ],
            )

    def test_dark_uint8_prediction_colors_keep_byte_intensity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            np.savez(
                root / "frame.npz",
                points=[[1, 2, 3]],
                colors=np.array([[1, 0, 1]], dtype=np.uint8),
            )
            output = root / "scene.ply"
            result = self.run_export("--predictions_dir", root, "--output", output)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                output.read_text().splitlines()[-1],
                "1.000000 2.000000 3.000000 1 0 1 0.8000",
            )

    def test_xyzrgb_byte_colors_are_not_clipped_to_white(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            np.save(root / "points.npy", [[1, 2, 3, 128, 64, 32]])
            output = root / "scene.ply"
            result = self.run_export(
                "--xyzrgb", root / "points.npy", "--output", output
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                output.read_text().splitlines()[-1],
                "1.000000 2.000000 3.000000 128 64 32 0.8000",
            )

    def test_unreadable_frames_report_actionable_error_without_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "bad.npz").write_bytes(b"not an archive")
            output = root / "scene.ply"
            result = self.run_export("--predictions_dir", root, "--output", output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("No readable point arrays", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
