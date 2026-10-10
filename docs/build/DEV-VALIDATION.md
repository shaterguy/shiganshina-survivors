# DEV VALIDATION Android artifact

This is an **incomplete development-validation package**, not a completed game or final art export. The original `assets/manifest.json` remains unchanged. `art_revision_status.final_export_allowed` stays `false` in both original source and packaged metadata. The normal build/export/sign/verify path still refuses the pending art.

## Actual unsigned artifact

- File: `dist/shiganshina-dev-validation-unsigned.apk`
- Bytes: `29,528,818`
- SHA-256: `42e1573e36c1f0017280d6e2608550dfd3e4826b8e9ed1a1ce51bae63178a5e0`
- Build report: `dist/shiganshina-dev-validation-unsigned.apk.build.json`
- Build-report SHA-256: `a8a9c6af32bf4178802ec2933eba09ddc6bada25301912abfa4c3584655d3900`
- Independent content audit: `dist/shiganshina-dev-validation-unsigned.apk.audit.json`
- Package: `com.shaterguy.shiganshina.dev`; version `0.1.0-dev1` / code `1`
- Architecture: ARM64 only; permissions: none; archive entries: 301
- Unsigned: requires the separately authorized existing device-local DEV key before Android installation. No key was created, opened, copied, or uploaded by this build.

## Exactly five temporary replacements

Only these stable IDs use the already approved `titan_basic_v2.png` artwork:

- `titan_runner`
- `titan_sweeper`
- `boss_charger`
- `boss_leaper`
- `boss_abnormal`

Approved basic PNG SHA-256: `e7debeea18672d55cd938f213a7738eb93c2a89c9783a201b30421e4e466a62c`.

Each replacement copies the basic frame geometry and animations, retains `export_blocked=true`, adds `development_only=true`, and declares `review_status=development_placeholder_not_final_approval`. `development_placeholder` records the excluded original path, SHA-256 and rejected status. Original rejected pixels are never staged. Entity behavior, IDs, combat rules and distinct attack patterns remain those of the original entities; only the unavailable art is temporarily substituted.

The top-level `development_validation` metadata declares the exact mode, sorted five IDs, basic fallback, source-manifest hash and incomplete notice. The permanent runtime banner says “DEV 미완료 · 5종 기본 외형 대체 · 보행 수정 중”. The Android launcher label identifies DEV VALIDATION. Other approved manifest art remains unchanged. Pending walking revisions and source/candidate previews are not promoted by this build.

## Build and verification

Godot `4.6.3.stable.official.7d41c59c4` and the official `android_debug-4.6.3.apk` template are pinned. Template SHA-256: `5cd4cfc1a8fc23ed45be5f0a36a6cc279d15b50a40c6ef69c89276895441cd1d`.

```sh
python tools/build/build_android.py --development-validation \
  --godot /usr/local/bin/godot \
  --template /path/to/android_debug-4.6.3.apk \
  --output dist/shiganshina-dev-validation-unsigned.apk

python tools/build/verify_android.py \
  dist/shiganshina-dev-validation-unsigned.apk \
  --development-validation --template /path/to/android_debug-4.6.3.apk
```

Existing output files are never overwritten. Choose a fresh output path for later builds. Export uses an isolated temporary project and editor profile, with no Android SDK, Java tools, signing keys, or user profile discoverable by Godot. Only runtime GDScript/scenes/data and manifest-allowlisted art are staged. The production filter accepts only runtime art/audio directories and excludes source, candidates, previews and rejected subdirectories.

Both Python and Godot require the precise explicit development mode and metadata. Missing metadata, changed fallback path/hash/approval, missing or additional blocked IDs, changed frame metadata, or a flipped final flag fail closed. The APK verifier compares the packaged manifest and game data with the expected staged source, checks engine runtime entries against the pinned template, and rejects unlisted files, unsupported ABIs, INTERNET permission, every excluded original art path/import path, and the five rejected PNG hashes even if disguised under an otherwise allowed imported-resource name.

The device-local `sign_android.py --development-validation` API can validate this same package without changing the default final-art gate. It still requires the existing pinned public certificate and caller-managed private files; the explicit flag is not permission to create or rotate credentials. The separate PHONE workflow owns all authorized signing and device actions.

## Verification evidence and remaining limits

- Python build tests: 44 passed. New staging/flag tests were observed RED before implementation; the disguised rejected-PNG archive regression was separately observed RED then GREEN.
- Godot export-gate checks: 22 passed after a RED missing-explicit-gate check.
- Full Godot suite: 3,567 checks, zero failures.
- Actual APK build: exit 0, followed by independent verifier exit 0.
- Default `build_android.py --check-ready`: exit 2, `art_review_pending`, as required.
- Independent ZIP audit: no rejected PNG payloads or source/candidate/preview paths; exactly five placeholders and `final_export_allowed=false` confirmed.
- Original manifest SHA-256 before/after: `cf3183c45f389ba00387c78ca0084924947a358d5e8ff1b5f1993e48318dde24`.
- Packaged development manifest SHA-256: `2eef6472d8d8da5b2404e7dc8f99c966018d760747c806c62a065aefc110e550`.

This artifact has not been signed or installed on an Android device during this build. Touch/gamepad feel, device GPU behavior and device save/resume remain to be tested on the target hardware. Headless tests and archive checks do not establish on-device play quality. The five art revisions and walking review remain open. This deliverable does not approve final art or grant final-release readiness.
