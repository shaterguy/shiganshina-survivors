"""Mechanical, lossless alpha-support trim of the explicit frozen 16 sources.

No painting, scaling, replacement source generation, or product activation.
Coordinates are pixel edges; source_offset maps packed coordinates to original
source coordinates, including the mandatory clear one-pixel border.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
from PIL import Image

ORDER = ['left_upper_arm', 'left_forearm', 'left_thigh', 'left_shin', 'left_foot',
         'right_thigh', 'right_shin', 'right_foot', 'posterior_underlap',
         'head_seam_underlap', 'neck', 'girdle', 'torso', 'head',
         'right_upper_arm', 'plate', 'right_forearm']
INPUT = 'recovery/armored-opposite-support-impact-sequence/render-inputs.json'
SOURCE_HASHES = 'recovery/armored-opposite-support-impact-sequence/SOURCE-HASHES.json'
HELD_MEASUREMENT = 'recovery/armored-opposite-support-impact-sequence/evidence/all-frame-measurements.json'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def alpha_hull(image):
    """Convex support of nonzero-alpha pixel cells with original pixel witnesses."""
    alpha = image.getchannel('A')
    pixels = alpha.load()
    points = {}
    for y in range(image.height):
        xs = [x for x in range(image.width) if pixels[x, y]]
        if not xs:
            continue
        for x in [xs[0], xs[-1]]:
            for dx, dy in [(0, 0), (1, 0), (0, 1), (1, 1)]:
                points.setdefault((x + dx, y + dy), {'point': [x + dx, y + dy], 'pixel': [x, y], 'alpha': pixels[x, y]})
    ordered = sorted(points)
    def cross(a, b, c):
        return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    lower, upper = [], []
    for p in ordered:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(ordered):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return [points[p] for p in lower[:-1] + upper[:-1]]


def trim_rgba(source, pivot):
    if source.mode != 'RGBA':
        raise ValueError('source must be lossless RGBA')
    box = source.getchannel('A').getbbox()
    if box is None:
        raise ValueError('source has no nonzero-alpha support')
    left, top, right, bottom = box
    packed = Image.new('RGBA', (right - left + 2, bottom - top + 2))
    packed.paste(source.crop(box), (1, 1))
    offset = [left - 1, top - 1]
    alpha_bytes = source.getchannel('A').tobytes()
    meta = {'original_size': list(source.size), 'trim_origin': [left, top],
            'trim_size': [right-left, bottom-top], 'padding': 1,
            'packed_size': list(packed.size), 'source_offset': offset,
            'uv_source_offset': [-offset[0], -offset[1]],
            'pivot_source': list(pivot),
            'pivot_packed': [pivot[0]-offset[0], pivot[1]-offset[1]],
            'source_rgba_sha256': sha(source.tobytes()),
            'source_alpha_sha256': sha(alpha_bytes),
            'nonzero_alpha_pixels': sum(x != 0 for x in alpha_bytes),
            'alpha_one_pixels': alpha_bytes.count(1),
            'alpha_support_hull': alpha_hull(source)}
    return packed, meta


def reconstruct_rgba(packed, meta):
    image = Image.new('RGBA', tuple(meta['original_size']))
    width, height = meta['trim_size']
    image.paste(packed.crop((1, 1, 1+width, 1+height)), tuple(meta['trim_origin']))
    return image


def verify_correspondence(source, packed, meta):
    restored = reconstruct_rgba(packed, meta)
    if source.size != restored.size or source.getchannel('A').tobytes() != restored.getchannel('A').tobytes():
        return False
    return all(a == b for a, b in zip(source.get_flattened_data(), restored.get_flattened_data()) if a[3])


def load_source(source_root, meta):
    source = Image.open(Path(source_root) / meta['source_path'])
    if source.mode != 'RGBA':
        raise ValueError('frozen source is not RGBA: ' + meta['source_path'])
    source.load()
    if meta.get('source_region'):
        x, y, width, height = meta['source_region']
        region = Image.new('RGBA', source.size)
        region.paste(source.crop((x, y, x+width, y+height)), (x, y))
        return region
    return source


def confined_source(source_root, relative_path):
    path = (source_root / relative_path).resolve(strict=True)
    path.relative_to(source_root)
    return path


def pack(source_root, output, frozen_root=None):
    source_root, output = Path(source_root).resolve(), Path(output)
    # Explicit relocation of immutable source records, not a search/fallback.
    # Frozen JSON bytes and all registered hashes remain unchanged.
    frozen_root = source_root if frozen_root is None else Path(frozen_root).resolve()
    inputs_path = confined_source(source_root, INPUT)
    data = json.loads(inputs_path.read_text())
    held_path = confined_source(source_root, HELD_MEASUREMENT)
    held = json.loads(held_path.read_text())
    if held['strict_all_frame_source_corner_gate_pass'] or held['maximum_conservative_face_source_corner_world'] <= 72.0:
        raise ValueError('inherited strict source-corner hold was changed')
    hashes_path = confined_source(source_root, SOURCE_HASHES)
    frozen = {Path(x['path']).relative_to(frozen_root).as_posix(): x['sha256'] for x in json.loads(hashes_path.read_text())}
    specs = {name: copy.deepcopy(part) for name, part in data['registration']['parts'].items()}
    assembly = Path(data['sources']['assembly_outputs'])
    specs.update({
        'torso': {'path': data['sources']['entry_torso'], 'pivot': [210, 1175]},
        'neck': {'path': data['sources']['neck'], 'pivot': [210, 1175]},
        'head_seam_underlap': {'path': data['sources']['head_seam_underlap'], 'pivot': [866, 610]},
        'head': {'path': str(assembly / 'source-original-head.png'), 'pivot': [866, 610]},
        'plate': {'path': str(assembly / 'source-original-near-plate.png'), 'pivot': [210, 1175]},
        'girdle': {'path': str(assembly / 'source-girdle.png'), 'pivot': [210, 1175]},
        'posterior_underlap': {'path': data['sources']['neck'], 'pivot': [210, 1175], 'source_region': [545, 515, 110, 40]},
    })
    if set(specs) != set(ORDER):
        raise ValueError('explicit source allowlist mismatch')
    parts, dependencies = {}, {}
    (output / 'parts').mkdir(parents=True, exist_ok=True)
    for name in ORDER:
        spec = specs[name]
        source_path = Path(spec['path']).relative_to(frozen_root).as_posix()
        path = confined_source(source_root, source_path)
        source_sha = sha(path.read_bytes())
        if frozen.get(source_path) != source_sha:
            raise ValueError('frozen source digest mismatch: ' + str(path))
        meta = {'source_path': source_path, 'source_sha256': source_sha}
        if spec.get('source_region'):
            meta['source_region'] = spec['source_region']
        source = load_source(source_root, meta)
        image, trim = trim_rgba(source, spec['pivot'])
        meta.update(trim)
        for field in ['native_axis', 'native_length', 'scale', 'width_scale']:
            if field in spec:
                meta[field] = spec[field]
        if name.endswith('_thigh') or name.endswith('_shin'):
            meta['target_bone_length'] = 60.5
        elif name.endswith('_upper_arm'):
            meta['target_bone_length'] = 39.0
        elif name.endswith('_forearm'):
            meta['target_bone_length'] = 35.0
        if 'target_bone_length' in meta:
            meta['fixed_width_scale'] = float(spec.get('width_scale', meta['target_bone_length'] / spec['native_length']))
        destination = output / 'parts' / (name + '.png')
        image.save(destination, compress_level=9)
        if not verify_correspondence(source, image, meta):
            raise ValueError('visible source RGBA correspondence failed: ' + name)
        meta.update({'texture_path': 'res://assets/art/rig/armored_runtime_v1/parts/' + name + '.png',
                     'packed_png_sha256': sha(destination.read_bytes()), 'packed_png_bytes': destination.stat().st_size})
        parts[name] = meta
        dependencies[source_path] = source_sha
    registration = {
        'version': 1, 'method': 'transparent-only lossless trim with clear 1px border',
        'canvas': [288, 288], 'anchor_px': [144, 280], 'anatomical_ground_y': 278,
        'source_scale': 0.085, 'torso_pivot_source': [210, 1175], 'head_pivot_source': [866, 610],
        'source_count': len(dependencies), 'parts': parts, 'layer_order': ORDER,
        'meshes': copy.deepcopy(data['meshes']),
        'dependencies': [{'path': p, 'sha256': h} for p, h in sorted(dependencies.items())],
        'input_path': INPUT, 'input_sha256': sha(inputs_path.read_bytes()),
        'source_hashes_path': SOURCE_HASHES, 'source_hashes_sha256': sha(hashes_path.read_bytes()),
        'untrimmed_rgba_bytes': sum(next(m['original_size'][0] * m['original_size'][1] * 4 for m in parts.values() if m['source_path'] == p) for p in dependencies),
        'packed_rgba_bytes': sum(m['packed_size'][0]*m['packed_size'][1]*4 for m in parts.values()),
        'packed_png_bytes': sum(m['packed_png_bytes'] for m in parts.values()),
        'import_resident_bytes': None, 'gpu_resident_bytes': None,
        'quality_holds': {'face_source_corner_reach': {
            'status': 'HOLD', 'reach': held['maximum_conservative_face_source_corner_world'],
            'shoulder_limit': 72.0, 'reason': 'inherited strict source-space clearance failure',
            'measurement_path': HELD_MEASUREMENT, 'measurement_sha256': sha(held_path.read_bytes()),
            'strict_gate_failure_waived': False}},
        'runtime_integrated': False, 'native_gpu_verified': False, 'final_export_allowed': False,
    }
    (output / 'registration.json').write_text(json.dumps(registration, indent=2, sort_keys=True) + '\n')
    return registration


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--frozen-root', type=Path, help='Original root recorded in unchanged frozen source JSON; defaults to source-root')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = pack(args.source_root, args.output, frozen_root=args.frozen_root)
    print(json.dumps({k: result[k] for k in ['source_count', 'untrimmed_rgba_bytes', 'packed_rgba_bytes', 'packed_png_bytes', 'final_export_allowed']}, indent=2))
