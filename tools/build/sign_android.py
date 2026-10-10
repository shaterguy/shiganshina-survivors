#!/usr/bin/env python3
"""Sign an already verified APK using caller-managed files. Never creates a key."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from android_common import BuildError, PIN, ROOT, sha256


def sign_command(command: list[str], settings: dict, source: Path, output: Path) -> list[str]:
    password_args = ['--ks-pass', 'file:' + settings['KEYSTORE_PASSWORD_FILE']]
    separate_password = settings.get('KEY_PASSWORD_FILE')
    if separate_password and separate_password != settings['KEYSTORE_PASSWORD_FILE']:
        password_args += ['--key-pass', 'file:' + separate_password]
    # apksigner tries the keystore password for the key by default. Reusing one
    # file source twice can consume a nonexistent second line.
    return command + ['sign', '--ks', settings['KEYSTORE_PATH'], '--ks-type', 'PKCS12', '--ks-key-alias', settings.get('KEY_ALIAS', 'shiganshina-dev'),
                      ] + password_args + ['--v1-signing-enabled', 'false', '--v2-signing-enabled', 'true',
                      '--v3-signing-enabled', 'true', '--v4-signing-enabled', 'false',
                      '--out', str(output), str(source)]


def verify_certificate(output: str, expected: str) -> str:
    expected = expected.lower().replace(':', '')
    if not re.fullmatch('[0-9a-f]{64}', expected):
        raise BuildError('EXPECTED_CERT_SHA256 is required: use the existing key certificate fingerprint')
    found = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$', output, re.MULTILINE)
    if len(found) != 1 or found[0].lower() != expected:
        raise BuildError('Signing certificate SHA-256 mismatch or unexpected signer count')
    return expected


def resolve_certificate_pin(env: dict) -> str:
    identity = json.loads((ROOT/'docs/build/dev-signer-public.json').read_text(encoding='utf-8'))
    expected = str(identity.get('certificate_sha256', '')).lower().replace(':', '')
    if identity.get('package') != PIN['android']['package'] or not re.fullmatch('[0-9a-f]{64}', expected):
        raise BuildError('Invalid public metadata for the existing DEV identity')
    supplied = env.get('EXPECTED_CERT_SHA256', expected).lower().replace(':', '')
    if supplied != expected:
        raise BuildError('EXPECTED_CERT_SHA256 conflicts with the existing DEV identity; key rotation needs a reviewed metadata change')
    return expected


def certificate_command(command: list[str], settings: dict, certificate: Path) -> list[str]:
    # Export only the public DER certificate; never export key material.
    return command + ['-exportcert', '-alias', settings.get('KEY_ALIAS', 'shiganshina-dev'),
                      '-keystore', settings['KEYSTORE_PATH'], '-storetype', 'PKCS12',
                      '-storepass:file', settings['KEYSTORE_PASSWORD_FILE'], '-file', str(certificate)]


def jdk_tool(name: str, env: dict) -> str:
    if env.get(name.upper()):
        path = Path(env[name.upper()]).expanduser()
    elif env.get('JAVA_HOME'):
        path = Path(env['JAVA_HOME']) / 'bin' / (name + '.exe' if os.name == 'nt' else name)
    else:
        path = Path(shutil.which(name) or '')
    if not path.is_file(): raise BuildError('A JDK with ' + name + ' is required for signing')
    return str(path.resolve())


def tool_command(name: str, env: dict) -> list[str]:
    explicit = env.get(name.upper())
    if explicit:
        path = Path(explicit).expanduser().resolve()
    else:
        sdk = env.get('ANDROID_SDK_ROOT') or env.get('ANDROID_HOME')
        version = env.get('ANDROID_BUILD_TOOLS_VERSION')
        if not sdk or not version:
            raise BuildError(f'Set {name.upper()} or ANDROID_SDK_ROOT and ANDROID_BUILD_TOOLS_VERSION')
        base = Path(sdk).expanduser() / 'build-tools' / version
        path = base / ('lib/apksigner.jar' if name == 'apksigner' else 'zipalign.exe' if os.name == 'nt' else 'zipalign')
    if not path.is_file(): raise BuildError(name + ' tool does not exist')
    if name == 'apksigner' and path.suffix == '.jar':
        return [jdk_tool('java', env), '-jar', str(path)]
    if path.suffix.lower() in ('.bat', '.cmd'):
        raise BuildError('Use APKSIGNER pointing to lib/apksigner.jar instead of a batch wrapper')
    return [str(path)]


def secret_file(value: str, name: str, root: Path) -> Path:
    # Stat only. Python never opens the keystore or either password file.
    path = Path(value).expanduser().absolute()
    if path.is_symlink() or not path.is_file(): raise BuildError(name + ' must be an existing ordinary file')
    path = path.resolve()
    if path.is_relative_to(root.resolve()): raise BuildError(name + ' must be outside the repository')
    if os.name != 'nt' and stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise BuildError(name + ' must be readable only by its owner (chmod 600)')
    return path


def run_tool(command: list[str], label: str, env: dict) -> str:
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL, env=env, timeout=180)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise BuildError(label + ' could not finish') from exc
    # Never print signing command lines or tool failure output containing private paths.
    if result.returncode: raise BuildError(label + ' failed; check local tool versions and supplied files')
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--template', type=Path, required=True)
    parser.add_argument('--development-validation', action='store_true', help='Sign only the explicit incomplete development package, preserving final=false')
    args = parser.parse_args()
    try:
        from android_common import read_manifest, verify_apk
        env = dict(os.environ)
        if any(env.get(key) for key in ('KEYSTORE_PASSWORD', 'KEY_PASSWORD', 'STORE_PASSWORD', 'ANDROID_KEYSTORE_PASSWORD')):
            raise BuildError('Plaintext password environment variables are forbidden; supply password-file paths')
        expected = resolve_certificate_pin(env)
        settings = {}
        for key in ('KEYSTORE_PATH', 'KEYSTORE_PASSWORD_FILE', 'KEY_PASSWORD_FILE'):
            if key == 'KEY_PASSWORD_FILE' and not env.get(key): continue
            if not env.get(key): raise BuildError(key + ' is required')
            settings[key] = str(secret_file(env[key], key, ROOT))
        settings['KEY_ALIAS'] = env.get('KEY_ALIAS', 'shiganshina-dev')
        source, output = args.input.resolve(), args.output.resolve()
        if output.exists() or output.with_suffix('.apk.signing.json').exists() or source == output: raise BuildError('Output must be a new path; existing files are never overwritten')
        if output.suffix.lower() != '.apk': raise BuildError('Output must end in .apk')
        manifest = read_manifest(ROOT, development_validation=args.development_validation)
        verify_apk(source, args.template, ROOT, manifest, development_validation=args.development_validation)
        input_hash = sha256(source)
        aligner, signer = tool_command('zipalign', env), tool_command('apksigner', env)
        keytool = [jdk_tool('keytool', env)]
        tool_env = {key: env[key] for key in ('PATH', 'JAVA_HOME', 'SystemRoot', 'SYSTEMROOT', 'WINDIR', 'HOME', 'USERPROFILE', 'TEMP', 'TMP', 'TMPDIR', 'LANG') if key in env}
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='shigan-sign-', dir=output.parent) as folder:
            aligned, signed = Path(folder)/'aligned.apk', Path(folder)/'signed.apk'
            public_certificate = Path(folder)/'public-certificate.der'
            run_tool(certificate_command(keytool, settings, public_certificate), 'public certificate preflight', tool_env)
            if sha256(public_certificate) != expected:
                raise BuildError('Keystore certificate does not match the existing DEV identity; signing was not attempted')
            run_tool(aligner + ['-P', '16', '4', str(source), str(aligned)], 'zipalign', tool_env)
            run_tool(sign_command(signer, settings, aligned, signed), 'apksigner sign', tool_env)
            cert = verify_certificate(run_tool(signer + ['verify', '--verbose', '--print-certs', str(signed)], 'apksigner verify', tool_env), expected)
            run_tool(aligner + ['-c', '-P', '16', '4', str(signed)], 'zipalign verify', tool_env)
            verify_apk(signed, args.template, ROOT, manifest, signed=True, development_validation=args.development_validation)
            if sha256(source) != input_hash: raise BuildError('Input APK changed during signing')
            report = {'package': PIN['android'], 'input_sha256': input_hash, 'output_sha256': sha256(signed), 'certificate_sha256': cert}
            if args.development_validation:
                report.update({'build_mode':'development-validation', 'development_only':True, 'final_export_allowed':False, 'development_validation':manifest['development_validation']})
            # Exclusive creation prevents overwriting even if another process raced us.
            with output.open('xb') as dest, signed.open('rb') as src: shutil.copyfileobj(src, dest)
        if sha256(output) != report['output_sha256']: raise BuildError('Published APK SHA-256 mismatch')
        with output.with_suffix('.apk.signing.json').open('x', encoding='utf-8') as stream:
            json.dump(report, stream, indent=2); stream.write('\n')
        print(json.dumps(report, indent=2))
        return 0
    except (BuildError, OSError, ValueError) as exc:
        print('SIGN_BLOCKED: ' + str(exc), file=sys.stderr)
        return 2

if __name__ == '__main__': sys.exit(main())
