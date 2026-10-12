"""Local tool tests: no network, SDK, signing keys or export approval needed."""
import importlib.util
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / 'tools/build'
sys.path.insert(0, str(TOOLS))

class AndroidToolingTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue((TOOLS / 'android_common.py').is_file(), 'missing fail-closed Android build tooling')
        self.mod = __import__('android_common')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def manifest(self):
        return {'assets': {'icon': {'path': 'res://assets/icon.png', 'sha256': '0'*64}},
                'art_revision_status': {'final_export_allowed': True}}

    def test_gate_rejects_explicit_art_block(self):
        m = self.manifest(); m['assets']['icon']['export_blocked'] = True
        with self.assertRaisesRegex(self.mod.BuildError, 'icon'):
            self.mod.check_readiness(m)

    def test_gate_rejects_final_review_false(self):
        m = self.manifest(); m['art_revision_status']['final_export_allowed'] = False
        with self.assertRaisesRegex(self.mod.BuildError, 'art_review_pending'):
            self.mod.check_readiness(m)

    def test_gate_rejects_missing_or_malformed_records(self):
        for m in ({}, {'assets': {}}, {'assets': {'x': 'broken'}},
                  {'assets': {'x': {'path': '../private.key'}}},
                  {'assets': {'x': {'path': 'res://assets/../private.key'}}},
                  {'assets': {'x': {'path': 'res://assets/x.png', 'export_blocked': 'false'}}}):
            with self.subTest(m=m), self.assertRaises(self.mod.BuildError):
                self.mod.check_readiness(m)

    def test_gate_accepts_valid_unblocked_manifest(self):
        self.mod.check_readiness(self.manifest())

    def test_pin_mismatch_fails(self):
        p = self.root / 'template.apk'; p.write_bytes(b'wrong')
        with self.assertRaisesRegex(self.mod.BuildError, 'SHA-256'):
            self.mod.verify_template(p)

    def test_staging_copies_only_runtime_and_manifest_assets(self):
        m = self.manifest()
        for name in ('project.godot', 'assets/icon.png', 'assets/unused.png', 'assets/private.key',
                     'game/a.gd', 'game/private.key', 'scenes/main.tscn', 'data/enemies.json',
                     'data/private.txt', 'chapters/chapter_01/map.json', 'docs/private.md',
                     'addons/chapter_export/plugin.cfg', 'addons/chapter_export/plugin.gd',
                     'tools/build/export_readiness.gd', 'tools/build/production_export_filter.gd'):
            p = self.root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(name)
        p = self.root / 'assets/manifest.json'; p.write_text(json.dumps(m))
        dest = self.root / 'staged'
        self.mod.stage_project(self.root, dest, m)
        copied = {p.relative_to(dest).as_posix() for p in dest.rglob('*') if p.is_file()}
        self.assertIn('assets/icon.png', copied)
        self.assertIn('game/a.gd', copied)
        self.assertIn('data/enemies.json', copied)
        self.assertFalse(copied & {'assets/unused.png', 'assets/private.key', 'game/private.key', 'data/private.txt', 'docs/private.md'})

    def test_staging_rejects_symlink_escape(self):
        if not hasattr(os, 'symlink'): self.skipTest('symlink unavailable')
        target = self.root / 'secret.png'; target.write_bytes(b'private')
        src = self.root / 'repo'; (src / 'assets').mkdir(parents=True)
        (src / 'assets/icon.png').symlink_to(target)
        with self.assertRaisesRegex(self.mod.BuildError, 'symlink'):
            self.mod.source_file(src, 'assets/icon.png')

    def test_engine_environment_cannot_find_sdk_or_user_profile(self):
        env = self.mod.engine_environment(self.root)
        self.assertNotIn('JAVA_HOME', env)
        self.assertNotIn('ANDROID_HOME', env)
        self.assertNotIn('ANDROID_SDK_ROOT', env)
        self.assertEqual(env['PATH'], '')
        self.assertEqual(Path(env['HOME']), self.root / 'home')
        self.assertTrue(Path(env['XDG_CONFIG_HOME']).is_dir())

    def test_manifest_reader_decodes_package_and_permissions(self):
        manifest = binary_manifest('com.shaterguy.shiganshina.dev', '0.1.0-dev3', 3)
        values = self.mod.parse_android_manifest(manifest)
        self.assertEqual(values['package'], 'com.shaterguy.shiganshina.dev')
        self.assertEqual(values['versionCode'], 3)
        self.assertEqual(values['versionName'], '0.1.0-dev3')
        self.assertEqual(values['permissions'], [])

    def test_manifest_reader_supports_long_utf8_strings(self):
        version='dev-'+'x'*300
        values=self.mod.parse_android_manifest(binary_manifest('com.shaterguy.shiganshina.dev', version, 1))
        self.assertEqual(values['versionName'],version)

    def test_manifest_reader_fails_on_truncation(self):
        with self.assertRaises(self.mod.BuildError):
            self.mod.parse_android_manifest(binary_manifest('x', 'v', 1)[:-1])

    def test_package_validation_rejects_internet(self):
        data = binary_manifest('com.shaterguy.shiganshina.dev', '0.1.0-dev3', 3, internet=True)
        with self.assertRaisesRegex(self.mod.BuildError, 'INTERNET'):
            self.mod.validate_package(self.mod.parse_android_manifest(data))

    def test_package_validation_rejects_wrong_package_and_version(self):
        for package, version, code in [('wrong', '0.1.0-dev3', 3), ('com.shaterguy.shiganshina.dev', 'wrong', 3), ('com.shaterguy.shiganshina.dev', '0.1.0-dev3', 4)]:
            with self.assertRaises(self.mod.BuildError):
                self.mod.validate_package(self.mod.parse_android_manifest(binary_manifest(package, version, code)))

    def test_signing_command_uses_password_file_never_content(self):
        signer = __import__('sign_android')
        settings = {'KEYSTORE_PATH': str(self.root/'key.jks'), 'KEYSTORE_PASSWORD_FILE': str(self.root/'password.txt'), 'KEY_ALIAS': 'shiganshina-dev'}
        command = signer.sign_command(['apksigner'], settings, self.root/'in.apk', self.root/'out.apk')
        self.assertIn('file:'+settings['KEYSTORE_PASSWORD_FILE'], command)
        self.assertEqual(command.count('file:'+settings['KEYSTORE_PASSWORD_FILE']), 1)
        self.assertNotIn('--key-pass', command)
        settings['KEY_PASSWORD_FILE']=str(self.root/'separate-key.pass')
        separate=signer.sign_command(['apksigner'],settings,self.root/'in.apk',self.root/'out.apk')
        self.assertIn('file:'+settings['KEY_PASSWORD_FILE'],separate)
        self.assertNotIn('pass:', ' '.join(command))
        self.assertNotIn('env:', ' '.join(command))
        self.assertIn('--v4-signing-enabled', command)

    def test_cert_pin_is_mandatory_and_must_match(self):
        signer = __import__('sign_android')
        output = 'Signer #1 certificate SHA-256 digest: ' + 'a'*64 + '\n'
        self.assertEqual(signer.verify_certificate(output, 'aa:'*31+'aa'), 'a'*64)
        for pin in ('', 'b'*64):
            with self.assertRaises(self.mod.BuildError): signer.verify_certificate(output, pin)
        with self.assertRaises(self.mod.BuildError): signer.verify_certificate(output+output.replace('#1', '#2'), 'a'*64)


def binary_manifest(package, version, code, internet=False):
    """Small real Android binary-XML fixture, with UTF-8 string-pool encoding."""
    strings = ['manifest', 'package', package, 'versionCode', 'versionName', version,
               'uses-permission', 'name', 'android.permission.INTERNET']
    chunks = []; offsets = []; stringdata = b''
    for value in strings:
        offsets.append(len(stringdata)); encoded=value.encode()
        encode_length=lambda n: bytes([n]) if n < 128 else bytes([0x80 | (n >> 8), n & 255])
        stringdata += encode_length(len(value)) + encode_length(len(encoded)) + encoded + b'\0'
    stringdata += b'\0' * ((-len(stringdata)) % 4)
    chunks.append(struct.pack('<HHIIIIII', 1, 28, 28+4*len(strings)+len(stringdata), len(strings), 0, 0x100, 28+4*len(strings), 0) + struct.pack('<'+'I'*len(strings), *offsets)+stringdata)
    def element(name, attributes):
        attrs = b''
        for key, val, kind in attributes:
            attrs += struct.pack('<IIIHBBI', 0xffffffff, strings.index(key), strings.index(val) if kind==3 else 0xffffffff, 8, 0, kind, strings.index(val) if kind==3 else val)
        size=36+len(attrs)
        return struct.pack('<HHIII', 0x102, 16, size, 1, 0xffffffff)+struct.pack('<IIHHHHHH',0xffffffff,strings.index(name),20,20,len(attributes),0,0,0)+attrs
    chunks.append(element('manifest',[('package',package,3),('versionCode',code,0x10),('versionName',version,3)]))
    if internet: chunks.append(element('uses-permission',[('name','android.permission.INTERNET',3)]))
    body=b''.join(chunks)
    return struct.pack('<HHI',3,8,len(body)+8)+body


class ArchiveAndWrapperTests(unittest.TestCase):
    def setUp(self):
        self.mod = __import__('android_common')
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        (self.root/'assets').mkdir()
        self.manifest={'assets': {'icon': {'path':'res://assets/icon.png','sha256':__import__('hashlib').sha256(b'icon').hexdigest()}}}
        (self.root/'assets/manifest.json').write_text(json.dumps(self.manifest))
        self.template=self.root/'template.zip'; self.apk=self.root/'out.zip'
        with zipfile.ZipFile(self.template,'w') as z:
            z.writestr('AndroidManifest.xml', b'original')
            z.writestr('classes.dex', b'pinned-engine-code')
            z.writestr('lib/arm64-v8a/libgodot_android.so', b'pinned-library')
        self.entries={'AndroidManifest.xml':binary_manifest('com.shaterguy.shiganshina.dev','0.1.0-dev3',3),
                      'classes.dex':b'pinned-engine-code','lib/arm64-v8a/libgodot_android.so':b'pinned-library',
                      'assets/assets/icon.png':b'icon', 'assets/project.binary':b'project', 'assets/assets/manifest.json':json.dumps(self.manifest).encode()}

    def check(self):
        self.assertTrue(hasattr(self.mod,'validate_archive'), 'missing APK content whitelist')
        with zipfile.ZipFile(self.apk,'w') as z:
            for name, value in self.entries.items(): z.writestr(name,value)
        with zipfile.ZipFile(self.apk) as z, zipfile.ZipFile(self.template) as template:
            return self.mod.validate_archive(z,template,self.root,self.manifest)

    def test_archive_accepts_minimal_whitelist(self):
        self.check()

    def test_archive_rejects_extra_art_or_secrets(self):
        for name in ('assets/assets/old.png','assets/keys/signing.jks','assets/docs/private.md','../escape','classes999.dex'):
            with self.subTest(name=name):
                self.entries[name]=b'bad'
                with self.assertRaisesRegex(self.mod.BuildError, 'not allowed|unsafe'): self.check()
                del self.entries[name]

    def test_archive_rejects_other_abi(self):
        self.entries['lib/x86/libgodot_android.so']=b'bad'
        with self.assertRaisesRegex(self.mod.BuildError, 'ABI'): self.check()

    def test_archive_rejects_missing_template_runtime_entry(self):
        with zipfile.ZipFile(self.template,'a') as z: z.writestr('classes2.dex',b'required-code')
        with self.assertRaisesRegex(self.mod.BuildError,'template runtime entry'):
            self.check()

    def test_archive_rejects_changed_vendor_code(self):
        self.entries['classes.dex']=b'changed'
        with self.assertRaisesRegex(self.mod.BuildError, 'template bytes'): self.check()

    def test_archive_rejects_stale_manifest(self):
        self.entries['assets/assets/manifest.json']=b'{}'
        with self.assertRaisesRegex(self.mod.BuildError, 'manifest'): self.check()

    def test_build_stops_before_engine_when_gate_closed(self):
        import subprocess
        script=TOOLS/'build_android.py'
        self.assertTrue(script.is_file(), 'missing build wrapper')
        # A malformed mock project is sufficient: no Godot executable is required.
        (self.root/'assets/manifest.json').write_text(json.dumps({'assets':{'blocked':{'path':'res://assets/x.png','sha256':'0'*64,'export_blocked':True}}}))
        result=subprocess.run([sys.executable,str(script),'--project',str(self.root),'--godot','/nonexistent/engine','--template','/nonexistent/template','--output',str(self.root/'never.apk')],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('art_review_pending',result.stderr)
        self.assertFalse((self.root/'never.apk').exists())

class SigningSafetyTests(unittest.TestCase):
    def setUp(self):
        self.mod=__import__('android_common'); self.sign=__import__('sign_android')
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name); self.repo=self.root/'repo'; self.repo.mkdir()

    def test_credential_path_inside_repo_is_rejected(self):
        p=self.repo/'key.jks'; p.touch(); p.chmod(0o600)
        with self.assertRaisesRegex(self.mod.BuildError,'outside'):
            self.sign.secret_file(str(p),'KEYSTORE_PATH',self.repo)

    def test_private_file_is_only_statted_and_accepted(self):
        p=self.root/'placeholder.pass'; p.touch(); p.chmod(0o600)
        self.assertEqual(self.sign.secret_file(str(p),'KEYSTORE_PASSWORD_FILE',self.repo),p)

    @unittest.skipIf(os.name=='nt','POSIX permissions')
    def test_world_readable_password_file_is_rejected(self):
        p=self.root/'placeholder.pass'; p.touch(); p.chmod(0o644)
        with self.assertRaisesRegex(self.mod.BuildError,'owner'):
            self.sign.secret_file(str(p),'KEYSTORE_PASSWORD_FILE',self.repo)

    def test_preflight_exports_only_public_certificate_with_file_password(self):
        self.assertTrue(hasattr(self.sign,'certificate_command'),'missing pre-sign public-certificate check')
        command=self.sign.certificate_command(['keytool'],{'KEYSTORE_PATH':'/private/key.p12','KEYSTORE_PASSWORD_FILE':'/private/key.pass','KEY_ALIAS':'shiganshina-dev'},self.root/'certificate.der')
        self.assertIn('-exportcert',command)
        self.assertIn('-storepass:file',command)
        self.assertNotIn('-genkeypair',command)
        self.assertNotIn('-storepass',command)

    def test_existing_dev_identity_is_default_and_cannot_be_overridden(self):
        self.assertTrue(hasattr(self.sign,'resolve_certificate_pin'),'missing existing-key certificate pin')
        expected='4256200e2c63dbfec3d0e9370ecca4b611ee11c65e1e2edad88003ea858c174c'
        self.assertEqual(self.sign.resolve_certificate_pin({}),expected)
        self.assertEqual(self.sign.resolve_certificate_pin({'EXPECTED_CERT_SHA256':expected.upper()}),expected)
        with self.assertRaisesRegex(self.mod.BuildError,'existing DEV identity'):
            self.sign.resolve_certificate_pin({'EXPECTED_CERT_SHA256':'b'*64})

    def test_explicit_tool_path_is_used(self):
        p=self.root/'zipalign'; p.touch()
        self.assertEqual(self.sign.tool_command('zipalign',{'ZIPALIGN':str(p)}),[str(p)])

    def test_discovery_requires_explicit_build_tools_version(self):
        with self.assertRaisesRegex(self.mod.BuildError,'ANDROID_BUILD_TOOLS_VERSION'):
            self.sign.tool_command('zipalign',{'ANDROID_SDK_ROOT':str(self.root)})

    def test_failure_output_never_leaks_tool_stderr(self):
        with self.assertRaises(self.mod.BuildError) as error:
            self.sign.run_tool([sys.executable,'-c',"import sys; print('DO_NOT_LEAK',file=sys.stderr); sys.exit(7)"],'fixture tool',{})
        self.assertNotIn('DO_NOT_LEAK',str(error.exception))

    def test_invalid_icon_is_a_clean_build_error(self):
        import hashlib
        path=self.repo/'assets/art/ui/game_icon.png'; path.parent.mkdir(parents=True); path.write_bytes(b'\x89PNG\r\n\x1a\n')
        manifest={'assets':{'icon':{'path':'res://assets/art/ui/game_icon.png','sha256':hashlib.sha256(path.read_bytes()).hexdigest()}}}
        with self.assertRaisesRegex(self.mod.BuildError,'512'):
            self.mod.verify_source_hashes(self.repo,manifest)

    def test_source_asset_hash_mismatch_is_rejected(self):
        (self.repo/'assets').mkdir(); (self.repo/'assets/a.png').write_bytes(b'wrong')
        with self.assertRaisesRegex(self.mod.BuildError,'Asset SHA-256 mismatch'):
            self.mod.verify_source_hashes(self.repo,{'assets':{'a':{'path':'res://assets/a.png','sha256':'0'*64}}})

if __name__ == '__main__': unittest.main()
