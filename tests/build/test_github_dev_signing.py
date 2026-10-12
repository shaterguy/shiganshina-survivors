"""Signing policy checks only: every credential/tool boundary is mocked."""
from contextlib import ExitStack, redirect_stderr, redirect_stdout
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/build'))
import android_common as common
import sign_android as signing

REPOSITORY = 'shaterguy/shiganshina-survivors'
FINGERPRINT = 'a' * 64  # Synthetic public test value, not an actual certificate.
SOURCE_HASH = 'b' * 64


class GithubDevSigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.repo = self.work/'project'
        self.identity_file = self.repo/'docs/build/github-dev-signer-public.json'
        self.identity_file.parent.mkdir(parents=True)
        self.identity = {
            'schema_version': 1, 'policy': 'github-new-dev',
            'repository': REPOSITORY, 'identity_id': 'github-dev-fixture',
            'package': common.PIN['android']['package'], 'key_alias': 'fixture-alias',
            'keystore_type': 'PKCS12', 'certificate_sha256': FINGERPRINT,
        }
        self.save_identity()
        self.env = {'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': REPOSITORY}

    def save_identity(self):
        self.identity_file.write_text(json.dumps(self.identity))

    def resolve(self, env=None, development=True):
        self.assertTrue(hasattr(signing, 'resolve_signing_identity'),
                        'missing explicit GitHub DEV policy')
        with patch.object(signing, 'ROOT', self.repo):
            return signing.resolve_signing_identity(
                self.env if env is None else env, github_new_dev=True,
                development_validation=development)

    def test_new_identity_has_no_dependency_on_historical_pin(self):
        # There is deliberately no dev-signer-public.json in this fixture.
        result = self.resolve()
        self.assertEqual(result['certificate_sha256'], FINGERPRINT)
        self.assertEqual(result['key_alias'], 'fixture-alias')
        self.assertEqual(result['identity_id'], 'github-dev-fixture')

    def test_legacy_default_remains_pinned(self):
        self.assertTrue(hasattr(signing, 'resolve_signing_identity'))
        result = signing.resolve_signing_identity({})
        self.assertEqual(result['policy'], 'historical-dev')
        self.assertEqual(result['certificate_sha256'], signing.resolve_certificate_pin({}))
        with self.assertRaises(common.BuildError):
            signing.resolve_signing_identity({'EXPECTED_CERT_SHA256': FINGERPRINT})

    def test_new_policy_requires_explicit_development_mode(self):
        with self.assertRaisesRegex(common.BuildError, 'development-validation'):
            self.resolve(development=False)

    def test_new_policy_requires_expected_github_context(self):
        for env in ({}, {'GITHUB_ACTIONS': 'false', 'GITHUB_REPOSITORY': REPOSITORY},
                    {'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': 'other/repository'}):
            with self.subTest(env=env), self.assertRaisesRegex(common.BuildError, 'GitHub'):
                self.resolve(env)

    def test_missing_new_metadata_never_falls_back_to_old_identity(self):
        self.identity_file.unlink()
        with self.assertRaisesRegex(common.BuildError, 'public identity'):
            self.resolve()

    def test_public_metadata_schema_and_binding_fail_closed(self):
        original = copy.deepcopy(self.identity)
        for key, value in [('schema_version', True), ('policy', 'historical-dev'),
                           ('repository', 'other/repository'), ('package', 'wrong.package'),
                           ('keystore_type', 'JKS'), ('identity_id', ''), ('identity_id', None),
                           ('key_alias', ''), ('certificate_sha256', 'UNSET'),
                           ('certificate_sha256', None)]:
            with self.subTest(key=key, value=value):
                self.identity = {**original, key: value}; self.save_identity()
                with self.assertRaises(common.BuildError): self.resolve()
        self.identity_file.write_text('[]')
        with self.assertRaises(common.BuildError): self.resolve()

    def test_identity_symlink_is_rejected(self):
        other = self.work/'other.json'; other.write_text(json.dumps(self.identity))
        self.identity_file.unlink(); self.identity_file.symlink_to(other)
        with self.assertRaises(common.BuildError): self.resolve()

    def test_environment_cannot_override_public_pin_or_alias(self):
        for extra in ({'EXPECTED_CERT_SHA256': 'c'*64}, {'KEY_ALIAS': 'wrong-alias'}):
            with self.subTest(extra=extra), self.assertRaises(common.BuildError):
                self.resolve({**self.env, **extra})
        result = self.resolve({**self.env, 'EXPECTED_CERT_SHA256': FINGERPRINT.upper(),
                               'KEY_ALIAS': 'fixture-alias'})
        self.assertEqual(result['certificate_sha256'], FINGERPRINT)

    def invoke(self, *, preflight_pin=FINGERPRINT, signed_pin=FINGERPRINT,
               input_pin=None, source_pin=SOURCE_HASH, omit=None, mutate_input=False):
        """Exercise the real main orchestration, replacing tools/credentials only."""
        source = self.work/'unsigned.apk'; source.write_bytes(b'unsigned fixture')
        output = self.work/'new-dev.apk'
        self.input_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        args = ['sign_android.py', '--input', str(source), '--output', str(output),
                '--template', str(self.work/'template.apk'), '--development-validation',
                '--github-new-dev']
        if omit != 'input': args += ['--expected-input-sha256', input_pin or self.input_hash]
        if omit != 'source': args += ['--expected-source-sha256', source_pin]
        self.labels = []
        def tool(command, label, env):
            self.labels.append(label)
            if label == 'apksigner sign':
                Path(command[command.index('--out') + 1]).write_bytes(b'signed fixture')
                self.assertEqual(command[command.index('--ks-key-alias') + 1], 'fixture-alias')
                if mutate_input: source.write_bytes(b'changed')
            if label == 'apksigner verify':
                return 'Signer #1 certificate SHA-256 digest: ' + signed_pin + '\n'
            return ''
        real_hash = signing.sha256
        def hash_file(path):
            if path.name == 'public-certificate.der': return preflight_pin
            return real_hash(path)
        self.stdout, self.stderr = io.StringIO(), io.StringIO()
        manifest = {'development_validation': {'mode': 'development-validation'},
                    'art_revision_status': {'final_export_allowed': False}}
        with ExitStack() as stack:
            stack.enter_context(patch.object(signing, 'ROOT', self.repo))
            stack.enter_context(patch.object(sys, 'argv', args))
            stack.enter_context(patch.dict(os.environ, {
                **self.env, 'KEYSTORE_PATH': '/MOCK_ONLY/key.p12',
                'KEYSTORE_PASSWORD_FILE': '/MOCK_ONLY/password-file'}, clear=True))
            self.secret_mock = stack.enter_context(patch.object(signing, 'secret_file',
                side_effect=lambda value, name, root: Path(value)))
            stack.enter_context(patch.object(signing, 'tool_command', side_effect=lambda name, env: [name]))
            stack.enter_context(patch.object(signing, 'jdk_tool', return_value='keytool'))
            stack.enter_context(patch.object(signing, 'run_tool', side_effect=tool))
            stack.enter_context(patch.object(signing, 'sha256', side_effect=hash_file))
            stack.enter_context(patch.object(common, 'read_manifest', return_value=manifest))
            self.archive_mock = stack.enter_context(patch.object(common, 'verify_apk', return_value={}))
            stack.enter_context(patch.object(common, 'stage_project', return_value={'source_sha256': SOURCE_HASH}))
            # Any accidental subprocess call is a test failure, never an actual signing operation.
            stack.enter_context(patch.object(signing.subprocess, 'run', side_effect=AssertionError('external execution forbidden')))
            stack.enter_context(redirect_stdout(self.stdout)); stack.enter_context(redirect_stderr(self.stderr))
            try: code = signing.main()
            except SystemExit as exc: code = exc.code
        return code, output

    def test_new_policy_verifies_both_signers_and_preserves_dev_identity(self):
        code, output = self.invoke()
        self.assertEqual(code, 0, self.stderr.getvalue())
        report = json.loads(output.with_suffix('.apk.signing.json').read_text())
        self.assertEqual(report['certificate_sha256'], FINGERPRINT)
        self.assertEqual(report['signing_policy'], 'github-new-dev')
        self.assertEqual(report['signing_identity_id'], 'github-dev-fixture')
        self.assertEqual(report['signing_repository'], REPOSITORY)
        self.assertEqual(report['source_sha256'], SOURCE_HASH)
        self.assertEqual(report['input_sha256'], self.input_hash)
        self.assertEqual(report['template_sha256'], common.PIN['template']['sha256'])
        self.assertEqual(report['package'], common.PIN['android'])
        self.assertTrue(report['development_only'])
        self.assertFalse(report['final_export_allowed'])
        self.assertEqual(self.labels, ['public certificate preflight', 'zipalign',
                         'apksigner sign', 'apksigner verify', 'zipalign verify'])
        self.assertEqual(self.archive_mock.call_count, 2)

    def test_missing_hashes_block_before_credentials_or_tools(self):
        for omitted in ('input', 'source'):
            with self.subTest(omitted=omitted):
                code, output = self.invoke(omit=omitted)
                self.assertEqual(code, 2)
                self.assertIn('required', self.stderr.getvalue())
                self.assertEqual(self.secret_mock.call_count, 0)
                self.assertEqual(self.labels, [])
                self.assertFalse(output.exists())

    def test_wrong_input_hash_blocks_before_credentials_or_tools(self):
        code, output = self.invoke(input_pin='c'*64)
        self.assertEqual(code, 2)
        self.assertIn('Input APK SHA-256 mismatch', self.stderr.getvalue())
        self.assertEqual(self.secret_mock.call_count, 0)
        self.assertEqual(self.labels, [])
        self.assertFalse(output.exists())

    def test_wrong_source_hash_blocks_before_credentials_or_tools(self):
        code, output = self.invoke(source_pin='c'*64)
        self.assertEqual(code, 2)
        self.assertIn('Source SHA-256 mismatch', self.stderr.getvalue())
        self.assertEqual(self.secret_mock.call_count, 0)
        self.assertEqual(self.labels, [])
        self.assertFalse(output.exists())

    def test_preflight_mismatch_prevents_sign_attempt(self):
        code, output = self.invoke(preflight_pin='c'*64)
        self.assertEqual(code, 2)
        self.assertEqual(self.labels, ['public certificate preflight'])
        self.assertFalse(output.exists())

    def test_output_signer_mismatch_prevents_publication(self):
        code, output = self.invoke(signed_pin='c'*64)
        self.assertEqual(code, 2)
        self.assertIn('apksigner sign', self.labels)
        self.assertFalse(output.exists())
        self.assertFalse(output.with_suffix('.apk.signing.json').exists())

    def test_input_mutation_prevents_publication(self):
        code, output = self.invoke(mutate_input=True)
        self.assertEqual(code, 2)
        self.assertIn('Input APK changed', self.stderr.getvalue())
        self.assertFalse(output.exists())


if __name__ == '__main__': unittest.main()
