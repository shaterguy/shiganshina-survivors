> dev5 keeps the established dev4 GitHub certificate SHA-256
> `0ea1f152a801330f69ca0301a638de283e665c814535b54f407b1974c6bd2ae0`.
> Do not regenerate or replace a signing key. Local export remains unsigned.

> Current dev5 identity: **진격의 거인 인류의 날개**, repository
> `shaterguy/wings-of-humanity`, package `com.shaterguy.wingsofhumanity.dev`.
> Local builds remain unsigned. Use the separately reviewed
> [GitHub signing contract](github-signing-input-contract.md) for this package.
> The historical key, PHONE paths, and backup instructions below describe only
> the old `com.shaterguy.shiganshina.dev` lineage. They do not authorize key lookup,
> recovery, signing, or migration for this package, and the default signer rejects it.

# Portable local Android DEV build

## Status and limits

This is a local, source-controlled build recipe. It needs no GitHub Actions, Work task, cloud build service, account token, or Gradle project. The standard Godot Android template can be assembled into an **unsigned** APK through the project's EditorPlugin; the usual `--export-debug` prerequisite check incorrectly insists on SDK/signing setup for this unsigned route. Do not replace this recipe with the old failed SceneTree exporter.

At the 2026-10-10 tooling checkpoint, these five art records remain blocked: `titan_runner`, `titan_sweeper`, `boss_charger`, `boss_leaper`, `boss_abnormal`. `art_revision_status.final_export_allowed` is also `false`. This snapshot may change during art review; the source manifest is authoritative.

```sh
python3 tools/build/build_android.py --check-ready
```

A nonzero `EXPORT_BLOCKED art_review_pending` result is intentional. Never toggle flags, delete rejected records or use older APK probes merely to make a build pass. The source art must be revised, reviewed, and approved through the normal project process. The Python wrapper checks before launching any tool, and the EditorPlugin independently checks again. The default final-art gate has no bypass. A separate, explicitly incomplete [development-validation build](DEV-VALIDATION.md) uses five approved basic-art placeholders, preserves the final=false marker, and excludes the rejected images. It is not final art approval. Tests may also use a separate tiny fixture app.

## 1. Prepare local tools once

The recipe is designed for Linux, macOS and Windows. The real-engine fixture was verified on Linux; native Windows/macOS execution is not yet verified. Obtain these from official sources on the build machine:

1. Python 3.10+ (standard library only for building/signing).
2. Official **standard, non-.NET Godot 4.6.3** for that machine's OS/architecture. Its `--version` must be exactly `4.6.3.stable.official.7d41c59c4`. On macOS the command can point to `Godot.app/Contents/MacOS/Godot`; on Windows to the Godot console `.exe`.
3. The matching [official export templates archive](https://downloads.godotengine.org/?version=4.6.3&flavor=stable&slug=export_templates.tpz&platform=templates). It is large. Extract only `templates/android_debug.apk` to a tools directory **outside the repository**, named `android_debug-4.6.3.apk`.

No installer, SDK license agreement, download, authentication, or signing-key setup is performed by the scripts. Verify your Godot download against its official release checksums before running it. The wrapper checks the engine's exact reported version; OS-specific engine binary hashes are not committed here.

Example extraction from an archive you already downloaded:

```sh
python3 -c "import zipfile; from pathlib import Path; z=zipfile.ZipFile('/absolute/path/to/Godot_v4.6.3-stable_export_templates.tpz'); p=Path('/absolute/path/to/tools/android_debug-4.6.3.apk'); p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(z.read('templates/android_debug.apk'))"
```

The extracted template must be exactly:

- Bytes: `124546428`
- SHA-256: `5cd4cfc1a8fc23ed45be5f0a36a6cc279d15b50a40c6ef69c89276895441cd1d`
- Pinned in `tools/build/toolchain.json`

The wrapper independently hashes the file and rejects any mismatch. It never downloads a replacement or accepts an unpinned override. Updating tool versions requires a reviewed source change, fresh upstream provenance and fresh export tests.

## 2. Check source and run tests

From a clean checkout of the same source commit, run:

```sh
bash tools/test.sh
python3 -m unittest discover -s tests/build -p 'test_*.py'
python3 tests/assets/test_canon_candidates.py
python3 tools/art/validate_assets.py
python3 tools/build/build_android.py --check-ready
```

The art commands require Pillow separately; these tools do not install it. Use a dedicated local Python environment if needed. `tools/test.sh` also fails on Godot `SCRIPT ERROR` and `ERROR` log lines, even if Godot accidentally returns status zero. The build-tool unit suite uses synthetic manifests/archives and does not need an SDK or signing key.

To exercise the successful export path before game art review finishes, optionally run the separate tiny-app smoke test. It does not change the game's manifest or retain an APK:

```sh
python3 tests/build/smoke_android_export.py \
  --godot /absolute/path/to/godot \
  --template /absolute/path/to/tools/android_debug-4.6.3.apk
```

## 3. Produce the unsigned APK

```sh
python3 tools/build/build_android.py \
  --godot /absolute/path/to/godot \
  --template /absolute/path/to/tools/android_debug-4.6.3.apk \
  --output dist/WingsOfHumanity-v0.1.0-dev5-unsigned.apk
```

If `godot` is on `PATH`, omit `--godot`. On Windows use `py -3` instead of `python3`, ordinary Windows paths, and a single-line command rather than POSIX backslash continuations.

The wrapper:

1. Rejects blocked, malformed or hash-mismatched asset records.
2. Verifies the pinned template and exact engine version.
3. Makes a fresh temporary source copy containing only game/scenes, runtime JSON, manifest-listed assets, the exact bundled Noto Sans KR font/import/OFL paths and the export plugin. The font and license are SHA-256 pinned; other files in the font directory are excluded. It rejects symlinked source files. It does not import a user's `.godot` cache, `.git`, docs, unused art, local SDK settings or credential files.
4. Uses isolated home/config/cache directories, an empty engine `PATH`, and no `JAVA_HOME`, `ANDROID_HOME` or `ANDROID_SDK_ROOT`. Godot cannot discover a user's Android SDK, signer or debug keystore through those routes. No key is generated.
5. Runs the real EditorPlugin after resource import. The direct plugin path preserves the art gate; signing remains disabled.
6. Validates Android binary manifest package/version, ARM64-only native libraries, absence of INTERNET permission, ZIP integrity, source JSON, manifest assets and an archive whitelist. Untouched engine files must match the pinned template bytes.
7. Publishes only after verification, plus a `.apk.build.json` report containing source-input digest, template digest, engine version and APK SHA-256. It refuses existing output/report paths.

Identity: `com.shaterguy.wingsofhumanity.dev`, version name `0.1.0-dev5`, version code `5`, ARM64. The app uses its own 512×512 icon. The resulting file is **unsigned and is not installable yet**.

Recheck an unsigned artifact against the current approved source:

```sh
python3 tools/build/verify_android.py dist/WingsOfHumanity-v0.1.0-dev5-unsigned.apk \
  --template /absolute/path/to/tools/android_debug-4.6.3.apk
```

This recipe pins build inputs and recreates a clean import environment. It does **not** claim byte-for-byte reproducibility across all hosts: ZIP timestamps and generated import/scene metadata can differ. Retain the source commit, tool pins and per-build report to audit each result. Cross-platform execution requires a compatible Godot binary; a phone/tablet alone is not automatically a supported build host.

## 4. Historical procedure: old-package local DEV signing

Signing needs a local JDK plus official Android SDK **Build Tools** that support `zipalign -P 16` (35.0.0 or newer). The full SDK/Gradle pipeline is not needed for unsigned export. Install/accept licenses yourself on your machine. Follow the official [apksigner](https://developer.android.com/tools/apksigner) and [zipalign](https://developer.android.com/tools/zipalign) guidance: alignment comes before signing, and nothing modifies the APK after it is signed.

The existing DEV signing key was provisioned on 2026-10-10 and remains on the owner's phone. Its public identity is pinned in [dev-signer-public.json](dev-signer-public.json): alias `shiganshina-dev`, PKCS12, certificate SHA-256 `4256200e2c63dbfec3d0e9370ecca4b611ee11c65e1e2edad88003ea858c174c`. The key and password have not been exported by these build tools.

This project never generates, uploads, prints or opens a private key/password in Python. The JDK `keytool` reads those files only to export the public certificate for a preflight check; `apksigner` reads them to perform signing. Python reads only the exported public certificate, never the keystore or password contents. Reuse this existing key after user-controlled recovery; do not generate a replacement merely to build on another machine.

Put the existing key and single-line UTF-8 password files **outside the repository**. On POSIX, each must have owner-only permissions (`chmod 600`); on Windows restrict access to your user with the OS permissions UI. Keep password files out of shell history, screenshots and chat. Do not use `KEYSTORE_PASSWORD`, `KEY_PASSWORD` or other plaintext password environment variables.

POSIX example; every value below is a path, alias, version or public certificate fingerprint, never a password:

```sh
export ANDROID_SDK_ROOT="/absolute/path/to/Android/sdk"
export ANDROID_BUILD_TOOLS_VERSION="35.0.0"
export JAVA_HOME="/absolute/path/to/jdk"
export KEYSTORE_PATH="/private/outside-repository/dev-keystore.p12"
export KEYSTORE_PASSWORD_FILE="/private/outside-repository/dev-keystore.pass"
export KEY_ALIAS="shiganshina-dev"
# EXPECTED_CERT_SHA256 is optional: the checked-in existing-key pin is the default.
# An explicitly supplied different fingerprint is rejected.
# If the key has a different password, set KEY_PASSWORD_FILE to its own file.
# Otherwise the keystore password file is used for both.
python3 tools/build/sign_android.py \
  --input dist/shiganshina-dev-unsigned.apk \
  --output dist/shiganshina-dev-signed.apk \
  --template /absolute/path/to/tools/android_debug-4.6.3.apk
```

Alternatively supply exact tool locations through `ZIPALIGN=/.../zipalign` and `APKSIGNER=/.../lib/apksigner.jar` (or the POSIX `apksigner` executable). Explicit tool paths take precedence; SDK discovery requires an explicit `ANDROID_BUILD_TOOLS_VERSION`, so it does not silently choose a different installed version. For Windows use `zipalign.exe` and `lib/apksigner.jar`; batch wrappers are intentionally rejected. The JDK supplies `keytool` for the public-certificate preflight; `KEYTOOL` can override its executable path. In PowerShell set variables with `$env:NAME="value"` and run `py -3`.

The checked-in public certificate SHA-256 is always enforced. You can independently compare it with a known-good APK using `apksigner verify --print-certs existing.apk`. The APK file's SHA-256 is a different hash. `EXPECTED_CERT_SHA256`, if supplied, must match the existing DEV identity; it cannot switch to a new key. There is no trust-on-first-use path. A deliberate future key change requires reviewed public-metadata and app-upgrade planning, rather than an environment-variable override.

The signer rechecks the art gate and unsigned archive, exports only the public certificate with [keytool `-exportcert` / `-storepass:file`](https://docs.oracle.com/en/java/javase/17/docs/specs/man/keytool.html), and checks its SHA-256 before any signing. A different key is rejected at this step. It then aligns, signs with `file:` password arguments, verifies the Android signature and one exact certificate fingerprint, checks alignment and signed contents, and publishes the final APK plus `.apk.signing.json`. It disables separate v4 `.idsig` generation. The report contains only package identity and public hashes. It never overwrites the unsigned file or an existing signed APK. Failure output suppresses tool output and signing command lines to avoid leaking private paths. No real signing has been validated until this procedure is run with the user's existing key; unit tests do not prove device installation.

## 5. Historical procedure: old-key backup and recovery

For the owner's minimal PHONE steps, use [한국어 키 백업·복원 안내](KEY-BACKUP-KO.md).

Source alone cannot recover a lost signing key. Android updates require the same signing identity; a different key generally requires uninstalling the old app, potentially losing local data. Keep the existing alias, certificate fingerprint, keystore password and optional separate key password recoverable.

User-controlled backup workflow (backs up both the existing key and its existing random password):

1. On PHONE, the existing files are `$HOME/.shiganshina-survivors/signing/dev-keystore.p12` and `dev-keystore.pass`. Keep them outside the source tree. With an already installed trusted GnuPG, create one encrypted bundle locally. The command contains only file paths; GnuPG prompts for a **new backup-encryption passphrase**. Never put that passphrase in the command line:

   ```sh
   set -o pipefail
   tar -C "$HOME/.shiganshina-survivors/signing" -cf - -- dev-keystore.p12 dev-keystore.pass | \
     gpg --symmetric --cipher-algo AES256 --output /offline-backup/shiganshina-dev-signing.tar.gpg
   ```

2. Keep two encrypted offline copies in separate safe locations. Store the backup-encryption passphrase in a password manager or another secure place separate from those copies. The key password is already inside the encrypted bundle; the backup-encryption passphrase must remain recoverable separately. Do not upload plaintext keys, password files or encrypted backups to this repository, chat, build artifacts or GitHub secrets.
3. Keep the public `dev-signer-public.json`, alias, package name and toolchain version with your recovery instructions. They identify the right key without revealing it.
4. On a trusted second machine, create a new private directory. Decrypt successfully **before** extracting; only extract the two expected file names. Example POSIX commands (the target directory must be new):

   ```sh
   umask 077
   mkdir /private/recovered-signing
   gpg --output /private/recovered-signing/restore.tar \
     --decrypt /offline-backup/shiganshina-dev-signing.tar.gpg && \
   tar -xf /private/recovered-signing/restore.tar -C /private/recovered-signing -- \
     dev-keystore.p12 dev-keystore.pass
   chmod 600 /private/recovered-signing/dev-keystore.p12 /private/recovered-signing/dev-keystore.pass
   ```

5. Set `KEYSTORE_PATH` and `KEYSTORE_PASSWORD_FILE` to the recovered files. Clone the same source commit, obtain the pinned tools/template, rebuild and sign. The checked-in certificate pin is verified before signing, so a different key is rejected. After verified recovery, remove the temporary plaintext `restore.tar` yourself; retain the original key and your encrypted backups. Windows users can perform equivalent steps using trusted local archive/encryption tools and owner-only folder permissions.

These backup and recovery steps must be performed locally by the key owner. The repository excludes common key/password/ciphertext forms, but `.gitignore` is only an accident-prevention layer; it does not protect a secret already committed under any name.

## Name and save-path compatibility (dev4)

The title has no colon and the Android label has no development suffix. The
in-game incomplete-art notice and export gate remain active. Chapter 1 remains
`시간시나구 탈출` (`chapter_01_shiganshina`); content and save schemas are unchanged.

On desktop, Godot previously sanitized the colon in the title to a hyphen.
The explicit `application/config/custom_user_dir_name` now preserves the same
`Godot/app_userdata/진격의 거인- 인류의 날개` path on Windows/macOS and
`godot/app_userdata/진격의 거인- 인류의 날개` on Linux/BSD. `user://saves` remains
unchanged. A disposable Linux Godot test verifies that the renamed project can
read the old directory. Windows/macOS paths follow Godot's documented layout
but have not been exercised here.

Android uses its app sandbox; the new package has separate storage and cannot
read old-package saves automatically. No existing save files are moved, changed,
or deleted. See [Godot data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html).
