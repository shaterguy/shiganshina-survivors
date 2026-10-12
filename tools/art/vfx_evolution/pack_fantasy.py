"""Mechanical nearest/palette packing of original raster VFX; never draws art.

Only this candidate directory and its descriptor are written. No manifest,
renderer, core data, geometry mask, pixel erasure, or source-art rewrite.
"""
import argparse
import hashlib
import json
import math
import subprocess
import tempfile
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / "assets/art/effects/vfx_fantasy_v1"
DOC = ROOT / "docs/art/vfx/fantasy-runtime-candidate.json"
SETTINGS = {
    "vfx_chain_lightning": {"source":"vfx_chain_lightning-generation-v1.png", "scale":.27, "pivot":[222,222],"cell":[128,64],"anchor":[12,32],"bounds":[12,0,104,64],"frame_pivots":[[222,244],[222,248],[222,248],[222,249],[222,230],[222,232],[222,232],[222,233]]},
    "vfx_storm_chain": {"source":"vfx_storm_chain-generation-v1.png", "scale":.22, "pivot":[222,222],"cell":[128,64],"anchor":[16,32],"bounds":[16,0,96,64],"frame_pivots":[[222,258],[222,261],[222,263],[222,265],[222,225],[222,224],[222,222],[222,221]]},
    "vfx_fire_zone": {"source":"vfx_fire_zone-generation-v1.png", "scale":.30, "pivot":[222,222],"cell":[128,128],"anchor":[64,64]},
    "vfx_inferno_zone": {"source":"vfx_inferno_zone-generation-v1.png", "scale":.27, "pivot":[222,222],"cell":[128,128],"anchor":[64,64]},
}


def magick(*args):
    subprocess.run(["magick", *map(str, args)], check=True, capture_output=True, text=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pack(art_id):
    settings = SETTINGS[art_id]
    requirement = {"cell_px":settings["cell"], "pivot_px":settings["anchor"], "contact_bounds_px":settings.get("bounds",[0,0,*settings["cell"]]), "notes":"Original fantasy contact effect; line is left anchored and field is center anchored. Same actual Core geometry; pending review."}
    source = ART / "source" / settings["source"]
    source_image = Image.open(source).convert("RGBA")
    iw, ih = source_image.size
    xs = settings.get("x_cuts", [round(i * iw / 4) for i in range(5)])
    ys = settings.get("y_cuts", [round(i * ih / 2) for i in range(3)])
    cw, ch = requirement["cell_px"]
    scale = settings["scale"]
    frame_dir = ART / f"{art_id}_frames"
    frame_dir.mkdir(exist_ok=True)
    frames = []
    audit = {"source_sha256": digest(source), "source_dimensions": [iw, ih], "same_scale_all_frames": scale,
             "opaque_pixels_clipped": 0, "geometry_mask_pixels_removed": 0,
             "operations": ["lossless source archive", "non-overlapping transparent-gap crop", "hard alpha 50%", "nearest resize with one uniform scale", "integer pivot translation", "24-palette nearest remap", "row-major 4x2 atlas"],
             "resampling_note": "Nearest downsampling changes pixel count. Clipped-pixel zero refers to opaque coverage cut off by extraction/canvas boundaries, not one-to-one high-resolution pixel retention.", "frames": []}
    with tempfile.TemporaryDirectory(prefix="vfx-pack-") as directory:
        work = Path(directory)
        for index in range(8):
            col, row = index % 4, index // 4
            left, right, top, bottom = xs[col], xs[col + 1], ys[row], ys[row + 1]
            raw, alpha, mapped = work / "raw.png", work / "alpha.png", work / "mapped.png"
            magick(source, "-crop", f"{right-left}x{bottom-top}+{left}+{top}", "+repage", "-channel", "A", "-threshold", "50%", "+channel", "-filter", "point", "-resize", f"{scale*100:.6f}%", "-define", "png:color-type=6", raw)
            resized = Image.open(raw).convert("RGBA")
            local_pivot = settings.get("frame_pivots", [settings["pivot"]] * 8)[index]
            source_pivot = [local_pivot[0] + col * iw / 4, local_pivot[1] + row * ih / 2]
            offset = [cw // 2 - round((source_pivot[0] - left) * scale), ch // 2 - round((source_pivot[1] - top) * scale)]
            points = [(x, y) for y in range(resized.height) for x in range(resized.width) if resized.getpixel((x, y))[3] == 255]
            clipped = sum(not (0 <= x + offset[0] < cw and 0 <= y + offset[1] < ch) for x, y in points)
            audit["opaque_pixels_clipped"] += clipped
            if clipped:
                raise ValueError(f"{art_id}/{index}: canvas would clip {clipped} opaque pixels")
            magick(raw, "-alpha", "extract", alpha)
            magick(raw, "-alpha", "off", "-dither", "None", "-remap", ROOT / "assets/art/palette.png", alpha, "-alpha", "off", "-compose", "CopyOpacity", "-composite", "-define", "png:color-type=6", mapped)
            frame = frame_dir / f"{index:02}.png"
            magick("-size", f"{cw}x{ch}", "xc:none", mapped, "-geometry", f"{offset[0]:+d}{offset[1]:+d}", "-compose", "Over", "-composite", "-define", "png:color-type=6", frame)
            image = Image.open(frame).convert("RGBA")
            pixels = [(x, y) for y in range(ch) for x in range(cw) if image.getpixel((x, y))[3]]
            radii = [math.hypot(x-cw//2, y-ch//2) for x, y in pixels]
            angles = [math.degrees(math.atan2(y-ch//2, x-cw//2)) for x, y in pixels]
            audit["frames"].append({"frame": index, "source_crop": [left, top, right, bottom], "source_pivot": source_pivot, "integer_translation_px": offset,
                                    "opaque_pixels_clipped": clipped, "opaque_bbox_px": image.getchannel("A").getbbox(), "opaque_pixel_count": len(pixels),
                                    "max_radius_px": max(radii), "angle_range_degrees": [min(angles), max(angles)], "sha256": digest(frame)})
            frames.append(frame)
    target = ART / settings.get("target", f"{art_id}.png")
    magick("montage", *frames, "-tile", "4x2", "-geometry", f"{cw}x{ch}+0+0", "-background", "none", "-define", "png:color-type=6", target)
    preview = ART / "previews" / f"{art_id}-nearest-2x.png"
    magick(target, "-background", "#30343b", "-alpha", "remove", "-filter", "point", "-resize", "200%", preview)
    metadata = {"path": "res://" + str(target.relative_to(ROOT)), "kind": "effect", "source_status": "NEW", "vfx_approved": False,
                "source_method": "Original built-in image generation/edit; mechanical nearest/palette/alpha raster packing. No SVG, generated geometry drawing, third-party assets or geometry masks.",
                "width": cw*4, "height": ch*2, "cell_w": cw, "cell_h": ch, "columns": 4,
                "anchor_px": requirement["pivot_px"], "vfx_bounds_px": requirement["contact_bounds_px"], "contact_frame": 0, "forward_axis": "+X",
                "animations": {"attack": {"frames": list(range(8)), "fps": 24, "loop": False}}, "sha256": digest(target),
                "source_path": str(source.relative_to(ROOT)), "source_sha256": digest(source), "preview_path": str(preview.relative_to(ROOT)),
                "notes": requirement["notes"], "approval_status": "CANDIDATE_PENDING_ACTUAL_RENDER_REVIEW"}
    return metadata, audit


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ids", nargs="+", choices=list(SETTINGS))
    args = parser.parse_args()
    descriptor = json.loads(DOC.read_text()) if DOC.exists() else {"schema_version": 1, "candidate_group": "vfx_fantasy_v1", "source_status": "NEW", "vfx_approved": False, "filter": "nearest", "mipmaps": False, "frame_order": "row_major_zero_based", "assets": {}, "packing_audit": {}}
    for art_id in args.ids:
        record, audit = pack(art_id)
        descriptor["assets"][art_id], descriptor["packing_audit"][art_id] = record, audit
        print(f"PACKED {art_id}: {record['path']} {record['width']}x{record['height']} {record['sha256']}")
    DOC.write_text(json.dumps(descriptor, indent=2) + "\n")
