"""Dependency-free, fail-closed Android build checks. No credential I/O or network."""
from __future__ import annotations
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PIN = json.loads((Path(__file__).with_name('toolchain.json')).read_text(encoding='utf-8'))
DEV_MODE = 'development-validation'
DEV_NOTICE = 'DEV VALIDATION | INCOMPLETE | 5 titan_basic art placeholders'
DEV_FALLBACK_PATH = 'res://assets/art/characters/titan_basic_v2.png'
DEV_FALLBACK_SHA256 = 'e7debeea18672d55cd938f213a7738eb93c2a89c9783a201b30421e4e466a62c'
# This narrow exception covers only the explicitly authorized five placeholders.
DEV_REJECTED_SHA256 = {
    'titan_runner': 'b4979340dd3339dfd062143e027d453b7e01c0a1f0b2b83ddfa93b09e690e722',
    'titan_sweeper': 'eb640f8a8c8617db7da4599554152d41162e7716f513335ed6ba56f002274f0f',
    'boss_charger': '7ee769802a176e95474e9ce9f88d22aab3aff6e967165cf82c06181c5c617bcb',
    'boss_leaper': '2da095171c0e6c8bff217837ab86f04120ff1aaebd3da7368ac34ca512e51efa',
    'boss_abnormal': '9de54f758a3ad0e2370c1d8f469272d4f68f3ab196dd7ee8a65d747ed1ec787a',
}
DEV_IDS = sorted(DEV_REJECTED_SHA256)
RUNTIME_ASSET_PATTERN = r'res://assets/(?:art/(?:characters|environment|effects|ui)/[^/]+\.png|audio/[^/]+\.wav)'

class BuildError(Exception):
    pass

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(part)
    return digest.hexdigest()

def read_manifest(root: Path, development_validation: bool = False) -> dict:
    try:
        raw = source_file(root, 'assets/manifest.json').read_bytes()
        manifest = json.loads(raw)
    except (OSError, ValueError) as exc:
        raise BuildError('Missing or invalid assets/manifest.json') from exc
    if development_validation and isinstance(manifest, dict) and 'development_validation' not in manifest:
        manifest = development_manifest(manifest, hashlib.sha256(raw).hexdigest())
    check_readiness(manifest, development_validation=development_validation)
    return manifest

def _manifest_fields(manifest: dict) -> tuple[list[str], dict]:
    if not isinstance(manifest, dict) or not isinstance(manifest.get('assets'), dict) or not manifest['assets']:
        raise BuildError('EXPORT_BLOCKED missing_manifest')
    blocked = []
    for name, asset in manifest['assets'].items():
        if not isinstance(asset, dict):
            raise BuildError(f'EXPORT_BLOCKED malformed asset: {name}')
        path = asset.get('path', '')
        parts = PurePosixPath(path.removeprefix('res://')).parts if isinstance(path, str) else ()
        if not isinstance(path, str) or not path.startswith('res://assets/') or '..' in parts or '\\' in path or not parts:
            raise BuildError(f'EXPORT_BLOCKED invalid asset path: {name}')
        if type(asset.get('export_blocked', False)) is not bool:
            raise BuildError(f'EXPORT_BLOCKED invalid export_blocked: {name}')
        if asset.get('export_blocked', False):
            blocked.append(name)
        if not re.fullmatch('[0-9a-f]{64}', str(asset.get('sha256', ''))):
            raise BuildError(f'EXPORT_BLOCKED missing asset SHA-256: {name}')
    status = manifest.get('art_revision_status', {})
    if not isinstance(status, dict) or type(status.get('final_export_allowed', True)) is not bool:
        raise BuildError('EXPORT_BLOCKED invalid art review status')
    return sorted(blocked), status

def check_readiness(manifest: dict, development_validation: bool = False) -> None:
    blocked, status = _manifest_fields(manifest)
    if development_validation:
        _check_development_manifest(manifest, blocked, status)
    elif blocked or not status.get('final_export_allowed', True) or 'development_validation' in manifest:
        raise BuildError('EXPORT_BLOCKED art_review_pending assets=' + ','.join(blocked))

def _check_fallback(manifest: dict) -> dict:
    basic = manifest['assets'].get('titan_basic', {})
    if (basic.get('path') != DEV_FALLBACK_PATH or basic.get('sha256') != DEV_FALLBACK_SHA256
            or basic.get('export_blocked') is not False
            or basic.get('review_status') != 'visual_reviewed_revision_2'
            or 'titan_basic' not in manifest.get('art_revision_status', {}).get('approved_character_ids', [])):
        raise BuildError('EXPORT_BLOCKED development fallback is not the pinned approved titan_basic')
    return basic

def _check_dev_scope(blocked: list[str], status: dict) -> None:
    if blocked != DEV_IDS or sorted(status.get('blocked_character_ids', [])) != DEV_IDS:
        raise BuildError('EXPORT_BLOCKED development requires exactly the five authorized blocked IDs')
    if status.get('final_export_allowed') is not False:
        raise BuildError('EXPORT_BLOCKED development must preserve final_export_allowed=false')

def development_manifest(original: dict, source_manifest_sha256: str) -> dict:
    """Create temporary metadata only; never write to the original asset manifest."""
    blocked, status = _manifest_fields(original)
    basic = _check_fallback(original)
    _check_dev_scope(blocked, status)
    if 'development_validation' in original or not re.fullmatch('[0-9a-f]{64}', source_manifest_sha256):
        raise BuildError('EXPORT_BLOCKED invalid development source manifest')
    staged = copy.deepcopy(original)
    staged['development_validation'] = {
        'mode': DEV_MODE, 'development_only': True, 'notice': DEV_NOTICE,
        'replacement_ids': DEV_IDS.copy(), 'fallback_asset_id': 'titan_basic',
        'source_manifest_sha256': source_manifest_sha256,
    }
    for name in DEV_IDS:
        old = original['assets'][name]
        if (old['path'] != f'res://assets/art/characters/{name}.png'
                or old['sha256'] != DEV_REJECTED_SHA256[name]
                or old.get('review_status') != 'rejected_incorrect_clothing'):
            raise BuildError('EXPORT_BLOCKED development source rejected asset changed: ' + name)
        record = copy.deepcopy(basic)
        record.update({
            'export_blocked': True, 'development_only': True,
            'reason': 'canon_revision_pending',
            'review_status': 'development_placeholder_not_final_approval',
            'development_placeholder': {
                'fallback_asset_id': 'titan_basic', 'original_path': old['path'],
                'original_sha256': old['sha256'], 'original_export_blocked': True,
                'original_review_status': old['review_status'],
            },
        })
        staged['assets'][name] = record
    check_readiness(staged, development_validation=True)
    return staged

def _check_development_manifest(manifest: dict, blocked: list[str], status: dict) -> None:
    _check_dev_scope(blocked, status)
    basic = _check_fallback(manifest)
    metadata = manifest.get('development_validation', {})
    if (not isinstance(metadata, dict) or metadata.get('mode') != DEV_MODE
            or metadata.get('development_only') is not True or metadata.get('notice') != DEV_NOTICE
            or metadata.get('replacement_ids') != DEV_IDS or metadata.get('fallback_asset_id') != 'titan_basic'
            or not re.fullmatch('[0-9a-f]{64}', str(metadata.get('source_manifest_sha256', '')))):
        raise BuildError('EXPORT_BLOCKED invalid development-validation metadata')
    for name, record in manifest['assets'].items():
        if not re.fullmatch(RUNTIME_ASSET_PATTERN, record['path']):
            raise BuildError('EXPORT_BLOCKED development asset is outside runtime whitelist: ' + name)
        if record['sha256'] in DEV_REJECTED_SHA256.values() or record['path'] in [f'res://assets/art/characters/{item}.png' for item in DEV_IDS]:
            raise BuildError('EXPORT_BLOCKED development contains rejected art: ' + name)
        if name not in DEV_IDS:
            if record.get('development_only', False) or 'development_placeholder' in record:
                raise BuildError('EXPORT_BLOCKED unexpected development placeholder: ' + name)
            continue
        if (record.get('development_only') is not True or record.get('export_blocked') is not True
                or record.get('review_status') != 'development_placeholder_not_final_approval'):
            raise BuildError('EXPORT_BLOCKED invalid development placeholder status: ' + name)
        for key in ('path', 'sha256', 'width', 'height', 'columns', 'cell_w', 'cell_h', 'anchor_px', 'animations'):
            if key not in basic or record.get(key) != basic[key]:
                raise BuildError('EXPORT_BLOCKED development fallback mismatch: ' + name)
        expected = {'fallback_asset_id': 'titan_basic', 'original_path': f'res://assets/art/characters/{name}.png',
                    'original_sha256': DEV_REJECTED_SHA256[name], 'original_export_blocked': True,
                    'original_review_status': 'rejected_incorrect_clothing'}
        if record.get('development_placeholder') != expected:
            raise BuildError('EXPORT_BLOCKED invalid development placeholder provenance: ' + name)

def manifest_bytes(root: Path, manifest: dict) -> bytes:
    if 'development_validation' in manifest:
        return (json.dumps(manifest, indent=2, ensure_ascii=False) + '\n').encode('utf-8')
    return source_file(root, 'assets/manifest.json').read_bytes()

def source_file(root: Path, relative: str) -> Path:
    path = root / relative
    if '..' in PurePosixPath(relative).parts or PurePosixPath(relative).is_absolute():
        raise BuildError('Unsafe source path')
    for parent in [path, *path.parents]:
        if parent == root: break
        if parent.is_symlink():
            raise BuildError('Source symlink is not allowed: ' + relative)
    if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
        raise BuildError('Source file missing or outside project: ' + relative)
    return path

def verify_source_hashes(root: Path, manifest: dict) -> None:
    for name, asset in manifest['assets'].items():
        path = source_file(root, asset['path'][6:])
        if sha256(path) != asset['sha256']:
            raise BuildError('Asset SHA-256 mismatch: ' + name)
    icon = source_file(root, 'assets/art/ui/game_icon.png').read_bytes()
    if len(icon) < 24 or icon[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack_from('>II', icon, 16) != (512, 512):
        raise BuildError('App icon must be the project-owned 512 x 512 PNG')

def verify_template(path: Path) -> str:
    if not path.is_file():
        raise BuildError('Android template missing; see docs/build/android-local.md')
    digest = sha256(path)
    if digest != PIN['template']['sha256']:
        raise BuildError('Android template SHA-256 does not match tools/build/toolchain.json')
    return digest

def stage_project(root: Path, dest: Path, manifest: dict) -> dict:
    """Fresh allowlisted checkout; no .git, user cache, credentials, docs or old art."""
    selected = {'project.godot', 'assets/manifest.json', 'addons/chapter_export/plugin.cfg',
                'addons/chapter_export/plugin.gd', 'tools/build/export_readiness.gd',
                'tools/build/production_export_filter.gd'}
    for folder, suffixes in [('game', {'.gd', '.uid', '.tres', '.tscn'}), ('scenes', {'.tscn', '.tres', '.uid'}),
                              ('data', {'.json'}), ('chapters', {'.json'})]:
        for file in (root / folder).rglob('*'):
            if file.is_file() and file.suffix in suffixes:
                selected.add(file.relative_to(root).as_posix())
    for asset in manifest['assets'].values():
        path = asset['path'][6:]
        selected.add(path)
        # Import settings are source metadata; the engine creates fresh imported bytes.
        if (root / (path + '.import')).exists(): selected.add(path + '.import')
    digest = hashlib.sha256()
    for relative in sorted(selected):
        source = source_file(root, relative)
        target = dest / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if relative == 'assets/manifest.json':
            target.write_bytes(manifest_bytes(root, manifest))
        else:
            shutil.copyfile(source, target)
        digest.update(relative.encode('utf-8') + b'\0' + bytes.fromhex(sha256(target)))
    return {'source_sha256': digest.hexdigest(), 'source_file_count': len(selected)}

def engine_environment(work: Path) -> dict:
    # Godot cannot discover Java/keytool, an Android SDK or a user's editor profile.
    env = {key: os.environ[key] for key in ('SystemRoot', 'WINDIR', 'SYSTEMROOT', 'LANG', 'LC_ALL') if key in os.environ}
    env['PATH'] = ''
    for name, sub in [('HOME', 'home'), ('USERPROFILE', 'home'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CACHE_HOME', 'cache'), ('XDG_CONFIG_HOME', 'config'),
                      ('APPDATA', 'config'), ('LOCALAPPDATA', 'data'), ('TEMP', 'tmp'),
                      ('TMP', 'tmp'), ('TMPDIR', 'tmp')]:
        folder = work / sub; folder.mkdir(parents=True, exist_ok=True); env[name] = str(folder)
    return env

def parse_android_manifest(data: bytes) -> dict:
    """Read the Android binary-XML string pool and start-element attributes."""
    try:
        if len(data) < 8 or struct.unpack_from('<HHI', data) != (3, 8, len(data)):
            raise ValueError('invalid XML header')
        strings = []; result = {'permissions': []}; offset = 8
        while offset < len(data):
            kind, header, size = struct.unpack_from('<HHI', data, offset)
            if header < 8 or size < header or offset + size > len(data): raise ValueError('bad chunk')
            end = offset + size
            if kind == 1:
                count, _, flags, start, _ = struct.unpack_from('<IIIII', data, offset + 8)
                if header < 28 or count > (size-header)//4 or start < header + count*4: raise ValueError('bad string pool')
                def length(pos, utf8):
                    unit = 1 if utf8 else 2; fmt = '<B' if utf8 else '<H'; high = 0x80 if utf8 else 0x8000
                    n = struct.unpack_from(fmt, data, pos)[0]; pos += unit
                    if n & high:
                        n = ((n & (high-1)) << (8 if utf8 else 16)) | struct.unpack_from(fmt, data, pos)[0]; pos += unit
                    return n, pos
                strings=[]
                for i in range(count):
                    pos = offset + start + struct.unpack_from('<I', data, offset + header + i*4)[0]
                    utf8 = bool(flags & 0x100)
                    n, pos = length(pos, utf8)
                    if utf8: n, pos = length(pos, True)
                    byte_count = n if utf8 else n*2
                    if pos+byte_count >= end: raise ValueError('truncated string')
                    strings.append(data[pos:pos+byte_count].decode('utf-8' if utf8 else 'utf-16le'))
            elif kind == 0x102:
                if header < 16 or size < header+20: raise ValueError('bad element')
                ext = offset + header
                _, name, attr_start, attr_size, count = struct.unpack_from('<IIHHH', data, ext)
                if attr_size < 20 or ext+attr_start+attr_size*count > end: raise ValueError('bad attributes')
                tag = strings[name]; attrs = {}
                for i in range(count):
                    pos = ext+attr_start+i*attr_size
                    _, name, raw, value_size, _, value_type, value = struct.unpack_from('<IIIHBBI', data, pos)
                    if value_size != 8: raise ValueError('bad value')
                    if raw != 0xffffffff: value = strings[raw]
                    elif value_type == 3: value = strings[value]
                    attrs[strings[name]] = value
                if tag == 'manifest':
                    if 'package' in result: raise ValueError('multiple manifests')
                    result.update(attrs)
                elif tag.startswith('uses-permission'):
                    result['permissions'].append(attrs.get('name', ''))
            offset = end
        if 'package' not in result: raise ValueError('missing package')
        return result
    except (ValueError, IndexError, struct.error, UnicodeError) as exc:
        raise BuildError('Invalid Android binary manifest') from exc

def validate_package(info: dict) -> None:
    expected = PIN['android']
    for attr, value in [('package', expected['package']), ('versionName', expected['version_name']), ('versionCode', expected['version_code'])]:
        if info.get(attr) != value: raise BuildError(f'APK {attr} mismatch')
    if 'android.permission.INTERNET' in info.get('permissions', []):
        raise BuildError('APK unexpectedly requests INTERNET permission')

def _resource_refs(raw: bytes) -> list[str]:
    try:
        return re.findall(r'"res://([^"\r\n]+)"', raw.decode('utf-8'))
    except UnicodeError as exc:
        raise BuildError('Invalid resource remap encoding') from exc

def validate_archive(archive: zipfile.ZipFile, template: zipfile.ZipFile, root: Path, manifest: dict) -> dict:
    names = archive.namelist(); name_set = set(names); vendor = set(template.namelist())
    if len(names) != len(name_set): raise BuildError('APK contains duplicate entries')
    for name in names:
        if name.startswith('/') or '..' in PurePosixPath(name).parts or '\\' in name:
            raise BuildError('APK contains unsafe entry')
        if name.startswith('lib/') and not name.startswith('lib/arm64-v8a/'):
            raise BuildError('APK contains an unexpected ABI')
    for required in ('AndroidManifest.xml', 'classes.dex', 'lib/arm64-v8a/libgodot_android.so', 'assets/project.binary', 'assets/assets/manifest.json'):
        if required not in name_set: raise BuildError('APK missing required entry: ' + required)
    for name in vendor:
        if name.startswith('lib/') and not name.startswith('lib/arm64-v8a/'): continue
        # Godot drops the unused Android themed-icon resource in the standard export.
        if name == 'res/mipmap-anydpi-v26/themed_icon.xml': continue
        if name not in name_set: raise BuildError('APK missing template runtime entry: ' + name)
    package = parse_android_manifest(archive.read('AndroidManifest.xml'))
    validate_package(package)
    if archive.read('assets/assets/manifest.json') != manifest_bytes(root, manifest):
        raise BuildError('APK asset manifest differs from the current source manifest')
    allowed = {'assets/assets/manifest.json', 'assets/project.binary', 'assets/assets.sparsepck', 'assets/_cl_',
               'assets/.godot/global_script_class_cache.cfg', 'assets/.godot/uid_cache.bin'}
    # Every JSON is deliberately added as raw data by the export filter.
    for folder in ('data', 'chapters'):
        for path in (root/folder).rglob('*.json'):
            relative = path.relative_to(root).as_posix(); member='assets/'+relative
            allowed.add(member)
            if member not in name_set or archive.read(member) != source_file(root,relative).read_bytes():
                raise BuildError('APK data missing or changed: ' + relative)
    for asset in manifest['assets'].values():
        relative = asset['path'][6:]; member = 'assets/'+relative
        allowed.update((member, member+'.import'))
        if member+'.import' in name_set:
            # Imported bytes must belong to this exact resource path, never arbitrary source art.
            prefix = '.godot/imported/' + Path(relative).name + '-' + hashlib.md5(asset['path'].encode()).hexdigest()
            refs = _resource_refs(archive.read(member+'.import'))
            imported = [ref for ref in refs if ref.startswith('.godot/imported/')]
            if not imported: raise BuildError('APK asset has no imported resource: ' + relative)
            for ref in imported:
                if ref not in (prefix+'.ctex', prefix+'.sample') or 'assets/'+ref not in name_set:
                    raise BuildError('APK unexpected imported resource: ' + relative)
                allowed.add('assets/'+ref)
        elif member in name_set:
            if hashlib.sha256(archive.read(member)).hexdigest() != asset['sha256']:
                raise BuildError('APK original asset SHA-256 mismatch: ' + relative)
        else:
            raise BuildError('APK is missing manifest asset: ' + relative)
    for folder in ('game', 'scenes'):
        for path in (root/folder).rglob('*'):
            if not path.is_file() or path.suffix not in ('.gd', '.tscn', '.tres'): continue
            relative = path.relative_to(root).as_posix(); member='assets/'+relative
            allowed.update((member, member+'.remap'))
            if path.suffix == '.gd': allowed.add(member[:-3]+'.gdc')
            if member+'.remap' in name_set:
                refs = _resource_refs(archive.read(member+'.remap'))
                if len(refs) != 1: raise BuildError('APK invalid script/scene remap')
                target = refs[0]
                if path.suffix == '.gd': valid = target == relative[:-3]+'.gdc'
                else:
                    extension = 'scn' if path.suffix == '.tscn' else 'res'
                    valid = bool(re.fullmatch(r'\.godot/exported/\d+/export-[0-9a-f]{32}-'+re.escape(path.stem)+r'\.'+extension, target))
                if not valid or 'assets/'+target not in name_set: raise BuildError('APK remap target is not allowed')
                allowed.add('assets/'+target)
    for name in names:
        if name in allowed: continue
        if name not in vendor: raise BuildError('APK entry not allowed: ' + name)
        # Godot rewrites Android settings, resource strings, and launcher icons.
        mutable = name in ('AndroidManifest.xml','resources.arsc') or bool(re.fullmatch(r'res/mipmap[^/]*/icon[^/]*\.(webp|png)',name))
        if not mutable and archive.read(name) != template.read(name):
            raise BuildError('APK changed pinned template bytes: ' + name)
    if 'development_validation' in manifest:
        check_readiness(manifest, development_validation=True)
        rejected_paths = [f'assets/assets/art/characters/{name}.png' for name in DEV_IDS]
        for name in names:
            if any(name.startswith(path) or Path(path).name + '-' in name for path in rejected_paths):
                raise BuildError('APK contains a rejected art path: ' + name)
            if hashlib.sha256(archive.read(name)).hexdigest() in DEV_REJECTED_SHA256.values():
                raise BuildError('APK contains rejected PNG bytes: ' + name)
    if archive.testzip() is not None: raise BuildError('APK CRC integrity failure')
    return {'package': package['package'], 'version_name': package['versionName'], 'version_code': package['versionCode'], 'abi': 'arm64-v8a', 'permissions': package['permissions'], 'archive_entries': len(names)}

def verify_apk(path: Path, template_path: Path, root: Path, manifest: dict, signed: bool = False, development_validation: bool = False) -> dict:
    check_readiness(manifest, development_validation=development_validation)
    verify_template(template_path)
    try:
        with zipfile.ZipFile(path) as archive, zipfile.ZipFile(template_path) as template:
            # v2/v3 signatures sit immediately before the ZIP central directory.
            with path.open('rb') as stream:
                stream.seek(max(0, archive.start_dir-16)); has_block = stream.read(16) == b'APK Sig Block 42'
            has_v1 = any(re.fullmatch(r'META-INF/[^/]+\.(RSA|DSA|EC|SF)', name, re.I) for name in archive.namelist())
            if not signed and (has_block or has_v1): raise BuildError('Expected unsigned APK, found a signing block')
            if signed and not has_block: raise BuildError('Signed APK lacks v2/v3 signing block')
            report = validate_archive(archive, template, root, manifest)
            if development_validation:
                rejected_paths = [f'assets/assets/art/characters/{name}.png' for name in DEV_IDS]
                report.update({'build_mode': DEV_MODE, 'development_only': True, 'final_export_allowed': False,
                               'development_validation': manifest['development_validation'],
                               'excluded_asset_paths': [path.removeprefix('assets/') for path in rejected_paths],
                               'excluded_asset_sha256': [DEV_REJECTED_SHA256[name] for name in DEV_IDS],
                               'asset_manifest_sha256': hashlib.sha256(manifest_bytes(root, manifest)).hexdigest()})
    except (OSError, zipfile.BadZipFile, KeyError) as exc:
        raise BuildError('Invalid APK archive') from exc
    report['sha256'] = sha256(path)
    return report
