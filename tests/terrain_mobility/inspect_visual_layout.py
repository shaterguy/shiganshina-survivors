"""Read-only asset-alpha/layout oracle. Run on the same local source as Godot QA."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
HOUSE_IDS = {"house_narrow", "house_bakery", "house_warehouse", "house_ruined"}
MAX_HOUSE_OCCLUSION = 0.12  # Small eave contact only; never another full facade.

def inspect():
    definitions = json.loads((ROOT / "data/world_props.json").read_text())
    templates = json.loads((ROOT / "chapters/chapter_01/city_templates.json").read_text())
    manifest = json.loads((ROOT / "assets/manifest.json").read_text())
    assets = {}
    for name in HOUSE_IDS:
        asset = manifest["assets"][name]
        source = ROOT / asset["path"].removeprefix("res://")
        image = Image.open(source).convert("RGBA")
        pixels = {(x - asset["anchor_px"][0], y - asset["anchor_px"][1]) for y in range(image.height) for x in range(image.width) if image.getpixel((x, y))[3] >= 128}
        assets[name] = {"pixels": pixels, "sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
    failures = []
    rows = []
    for template in templates["templates"]:
        houses = [s for s in template["slots"] if s["definition_id"] in HOUSE_IDS]
        own = [(s, {(x+s["position"][0], y+s["position"][1]) for x,y in assets[s["definition_id"]]["pixels"]}) for s in houses]
        worst = 0.0
        # Include all neighboring template combinations, not merely a repeated
        # center chunk or a cropped camera that hides a bad seam.
        comparisons = [(template, 0, 0)] + [(other, dx, dy) for other in templates["templates"] for dx,dy in [(-768,0),(768,0),(0,-768),(0,768),(-768,-768),(768,-768),(-768,768),(768,768)]]
        for other, dx, dy in comparisons:
            for target in (s for s in other["slots"] if s["definition_id"] in HOUSE_IDS):
                for source, pixels in own:
                    if dx == dy == 0 and source["slot_id"] == target["slot_id"]: continue
                    x = target["position"][0] + dx
                    y = target["position"][1] + dy
                    if abs(source["position"][0] - x) > 192 or abs(source["position"][1] - y) >= 192: continue
                    target_pixels = {(px+x, py+y) for px,py in assets[target["definition_id"]]["pixels"]}
                    overlap = len(pixels & target_pixels)
                    ratio = overlap / min(len(pixels), len(target_pixels))
                    worst = max(worst, ratio)
                    if ratio > MAX_HOUSE_OCCLUSION:
                        failures.append({"kind": "stacked_house_silhouette", "template": template["template_id"], "slot": source["slot_id"], "other_template": other["template_id"], "other_slot": target["slot_id"], "neighbor": [dx,dy], "overlap_ratio": round(ratio, 5)})
        rows.append({"template": template["template_id"], "house_count": len(houses), "prop_count": len(template["slots"]), "summed_opaque_house_pixels": sum(len(pixels) for _,pixels in own), "worst_pair_occlusion": round(worst,5)})
    narrow = definitions["definitions"]["house_narrow"]
    base = {(x,y) for x,y in assets["house_narrow"]["pixels"] if y >= -52}
    low = min(x for x,y in base)
    high = max(x for x,y in base) + 1
    foot = narrow["ground_footprint"]
    if foot[0] > low or foot[0]+foot[2] < high or foot[2] > high-low+8:
        failures.append({"kind": "narrow_wall_floor_mismatch", "opaque_base_span": [low,high], "ground_footprint": foot})
    result = {"checks": "actual alpha overlap across all template seams, narrow wall/floor calibration", "templates_sha256": hashlib.sha256((ROOT/"chapters/chapter_01/city_templates.json").read_bytes()).hexdigest(), "props_sha256": hashlib.sha256((ROOT/"data/world_props.json").read_bytes()).hexdigest(), "assets": {k:{"sha256":v["sha256"],"opaque_pixels":len(v["pixels"])} for k,v in assets.items()}, "districts":rows,"failures":failures}
    return result

if __name__ == "__main__":
    result = inspect()
    out = ROOT / ".qa/dev5-city-layout-visual.json"
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({"CITY_LAYOUT_VISUAL":result["districts"],"failure_count":len(result["failures"]),"first_failures":result["failures"][:8]}))
    raise SystemExit(1 if result["failures"] else 0)
