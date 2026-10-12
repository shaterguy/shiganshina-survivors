"""Template-free checks consume only fixed APK bytes; no key/tool execution."""
import struct
from pathlib import Path
import sys
import tempfile
import unittest
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/build'))
import android_common as common
import sign_android as signing
from test_android_tooling import binary_manifest


class VerifiedSigningPayloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        pin = common.PIN['android']
        self.entries = {'AndroidManifest.xml': binary_manifest(pin['package'], pin['version_name'], pin['version_code']),
                        'classes.dex': b'fixed payload'}

    def apk(self, name='input.apk', signed=False, duplicate=False):
        path = self.root/name
        with zipfile.ZipFile(path,'w') as archive:
            for key, value in self.entries.items(): archive.writestr(key, value)
            if duplicate:
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore'); archive.writestr('classes.dex', b'duplicate')
        if signed:
            # Container marker only; apksigner verification is a separate mandatory step.
            data = path.read_bytes(); offset = data.index(b'PK\x01\x02')
            data = data[:offset] + b'APK Sig Block 42' + data[offset:]
            end = data.rindex(b'PK\x05\x06')
            data = data[:end+16] + struct.pack('<I', offset+16) + data[end+20:]
            path.write_bytes(data)
        return path

    def check(self, path, signed=False):
        self.assertTrue(hasattr(signing, 'verified_payload'), 'missing fixed-input payload verification')
        return signing.verified_payload(path, signed=signed)

    def test_signing_block_does_not_change_payload_identity(self):
        self.assertEqual(self.check(self.apk()), self.check(self.apk('signed.apk', signed=True), signed=True))

    def test_changed_entry_changes_identity(self):
        before = self.check(self.apk())
        self.entries['classes.dex'] = b'changed'
        self.assertNotEqual(before, self.check(self.apk('changed.apk')))

    def test_rejects_duplicate_entries(self):
        with self.assertRaisesRegex(common.BuildError, 'duplicate'):
            self.check(self.apk(duplicate=True))

    def test_rejects_unsafe_entries(self):
        self.entries['../outside'] = b'bad'
        with self.assertRaisesRegex(common.BuildError, 'unsafe'):
            self.check(self.apk())

    def test_rejects_existing_or_missing_signatures(self):
        with self.assertRaisesRegex(common.BuildError, 'unsigned'):
            self.check(self.apk(signed=True))
        with self.assertRaisesRegex(common.BuildError, 'signing block'):
            self.check(self.apk('missing.apk'), signed=True)
        self.entries['META-INF/OWNER.RSA'] = b'old signature'
        with self.assertRaisesRegex(common.BuildError, 'signature'):
            self.check(self.apk('v1.apk'))

    def test_rejects_encrypted_entry_flags(self):
        path = self.apk()
        data = bytearray(path.read_bytes())
        for signature, flag_offset in [(b'PK\x03\x04', 6), (b'PK\x01\x02', 8)]:
            offset = data.index(signature) + flag_offset
            flags = struct.unpack_from('<H', data, offset)[0]
            struct.pack_into('<H', data, offset, flags | 1)
        path.write_bytes(data)
        with self.assertRaisesRegex(common.BuildError, 'encrypted'):
            self.check(path)

    def test_rejects_wrong_package(self):
        self.entries['AndroidManifest.xml'] = binary_manifest('wrong', '0.1.0-dev4', 4)
        with self.assertRaisesRegex(common.BuildError, 'package'):
            self.check(self.apk())

    def test_rejects_malformed_archive(self):
        path = self.root/'bad.apk'; path.write_bytes(b'not a zip')
        with self.assertRaises(common.BuildError): self.check(path)


if __name__ == '__main__': unittest.main()
