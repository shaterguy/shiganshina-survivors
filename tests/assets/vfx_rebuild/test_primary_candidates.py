"""Candidate-only raster contract. Does not load game scenes or approve assets."""
import hashlib
import json
import math
import os
import unittest
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
IDS = os.environ.get("VFX_IDS", "vfx_blade_crescent,vfx_spin_double_ring,vfx_cannon_shell,vfx_cannon_contact_blast,vfx_cannon_dust_ring").split(",")


class PrimaryCandidateContracts(unittest.TestCase):
    def test_blade_contact_reaches_authored_sector_tips(self):
        descriptor = json.loads((ROOT / "docs/art/vfx/primary-runtime-candidate.json").read_text())
        path = ROOT / descriptor["assets"]["vfx_blade_crescent"]["path"].removeprefix("res://")
        self.assertTrue(path.is_file())
        frame = Image.open(path).convert("RGBA").crop((0, 0, 128, 128))
        angles = [math.degrees(math.atan2(y-64, x-64)) for y in range(128) for x in range(128) if frame.getpixel((x, y))[3]]
        self.assertLessEqual(min(angles), -70, "Contact must visibly reach the upper authored 150-degree sector tip")
        self.assertGreaterEqual(max(angles), 70, "Contact must visibly reach the lower authored 150-degree sector tip")

    def test_raster_candidate_contracts(self):
        path = ROOT / "docs/art/vfx/primary-runtime-candidate.json"
        self.assertTrue(path.is_file(), "Candidate descriptor must exist")
        descriptor = json.loads(path.read_text())
        requirements = {r["art_id"]: r for r in json.loads((ROOT / "data/combat_vfx.json").read_text())["art_requirements"]}
        palette = {tuple(bytes.fromhex(c[1:])) for c in json.loads((ROOT / "assets/manifest.json").read_text())["palette"]}
        for art_id in IDS:
            with self.subTest(art_id=art_id):
                self.assertIn(art_id, descriptor["assets"])
                record = descriptor["assets"][art_id]
                requirement = requirements[art_id]
                self.assertIs(record["vfx_approved"], False)
                self.assertEqual(record["source_status"], "NEW")
                self.assertEqual(record["anchor_px"], requirement["pivot_px"])
                self.assertEqual(record["vfx_bounds_px"], requirement["contact_bounds_px"])
                self.assertEqual(record["contact_frame"], 0)
                self.assertEqual(record["forward_axis"], "+X")
                self.assertEqual(record["animations"]["attack"]["frames"], list(range(8)))
                self.assertIs(record["animations"]["attack"]["loop"], False)
                asset = ROOT / record["path"].removeprefix("res://")
                self.assertEqual(hashlib.sha256(asset.read_bytes()).hexdigest(), record["sha256"])
                source = ROOT / record["source_path"]
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), record["source_sha256"])
                image = Image.open(asset)
                self.assertEqual(image.mode, "RGBA")
                cw, ch = requirement["cell_px"]
                self.assertEqual(image.size, (cw * 4, ch * 2))
                pixels = list(image.get_flattened_data())
                self.assertEqual({p[3] for p in pixels}, {0, 255})
                self.assertTrue({p[:3] for p in pixels if p[3]} <= palette)
                frame_hashes = set()
                for index in range(8):
                    frame = image.crop((index % 4 * cw, index // 4 * ch, (index % 4 + 1) * cw, (index // 4 + 1) * ch))
                    frame_hashes.add(hashlib.sha256(frame.tobytes()).hexdigest())
                    self.assertIsNotNone(frame.getchannel("A").getbbox())
                    if art_id != "vfx_cannon_shell":
                        for y in range(ch):
                            for x in range(cw):
                                if frame.getpixel((x, y))[3] == 0:
                                    continue
                                dx, dy = x - cw / 2, y - ch / 2
                                self.assertLessEqual(math.hypot(dx, dy), cw / 2, f"{art_id}/{index}: outside core disk")
                                if art_id == "vfx_blade_crescent":
                                    self.assertLessEqual(abs(math.degrees(math.atan2(dy, dx))), 75, f"{art_id}/{index}: outside 150-degree sector")
                    if art_id in ("vfx_spin_double_ring", "vfx_cannon_dust_ring"):
                        self.assertEqual(frame.getpixel((cw // 2, ch // 2))[3], 0)
                self.assertEqual(len(frame_hashes), 8, "Eight distinct authored frames required")
                audit = descriptor["packing_audit"][art_id]
                self.assertEqual(audit["opaque_pixels_clipped"], 0)
                self.assertEqual(audit["geometry_mask_pixels_removed"], 0)


if __name__ == "__main__":
    unittest.main()
