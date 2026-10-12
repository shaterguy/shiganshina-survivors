# GitHub DEV signing input contract

This is a local candidate for signing an already built APK. It is not a
configured or executed GitHub workflow. Builds, gameplay tests, and resource
validation remain local. GitHub performs only signing and directly related
input, package, signature, and output integrity checks.

The user no longer requires upgrade compatibility with the previous installed
DEV app. A selected GitHub-held identity may therefore establish a different
DEV signing lineage. The renamed product uses `com.shaterguy.wingsofhumanity.dev`,
version name `0.1.0-dev4`, version code `4`, ABI `arm64-v8a`. All development
and incomplete-art markers remain unchanged, including
`final_export_allowed=false`. A different certificate for the same package
does not make it an in-place update or a second co-installable app. No uninstall
or device operation is implied or performed.

The intended repository is `shaterguy/wings-of-humanity`. The package change
creates a separate Android app sandbox; it is not an in-place dev3 update and
does not automatically move saves from the old app. No save schema, chapter
identity, map data, or content fingerprint changes accompany this rename.

## One identity, explicitly selected

The historical default path still checks `docs/build/dev-signer-public.json`,
which remains bound to `com.shaterguy.shiganshina.dev`. It deliberately rejects
the renamed package; its historical certificate and custody record are not
rewritten or used to constrain the selected GitHub DEV identity.
For this new route, the user's latest instruction supersedes the PHONE key
lookup/recovery procedure, mandatory dev1-certificate continuity, and prohibition
on GitHub Secrets in `docs/build/android-local.md`, `docs/build/KEY-BACKUP-KO.md`,
and historical `dev-signer-public.json` custody metadata. Those documents remain
historical evidence for prior artifacts. They do not authorize phone discovery,
key recovery, or exporting a key to the local build environment. The repository
is public, regardless of any old document calling it private.

The new path requires `--github-new-dev --development-validation` and the
separate, reviewed public file `docs/build/github-dev-signer-public.json`.
The `.example.json` file is intentionally incomplete and is never loaded by
the signer. Do not put secret values in either file.

The public identity contains the exact repository, stable identity ID, package,
JKS or PKCS12 key type, key alias, and SHA-256 of the selected public DER certificate. The
fingerprint is established independently for the intended GitHub signing
identity before signing. Do not learn an arbitrary certificate during signing
and automatically accept it. `EXPECTED_CERT_SHA256` and `KEY_ALIAS`, if supplied,
must agree with the reviewed public record. The new path never falls back to the
historical certificate, key alias, or missing metadata.

`GITHUB_ACTIONS=true` and the exact repository name are required as accidental
local-execution guards. They are not authentication or an authorization boundary;
the approved workflow, exact trusted source checkout, and GitHub secret access
controls supply that boundary. No untrusted PR, fork, arbitrary source branch,
or caller-provided script should receive signing secrets.

## Minimum non-secret inputs

1. The final local unsigned APK and its trusted local `.apk.build.json` report.
   Supply the report's APK `sha256` as `--expected-input-sha256`. Do not derive
   the expected digest only from the remote file being checked.
2. The exact approved source checkout matching that APK, preserved under an
   immutable GitHub commit before delivery. Supply the report's `source_sha256`
   as `--expected-source-sha256`. This is the builder's sorted staged-source
   fingerprint, not a Git commit SHA. The signer reuses `stage_project` to
   recompute it without invoking Godot. Required sources include runtime code,
   scenes, data, manifest-selected assets, font inputs, the narrow armored
   registration/17-part bundle, and the matching validator/export tools.
   The source commit also pins signing code, public identity and toolchain;
   these are not all covered by the staged-source fingerprint.
3. For the full template-revalidation path, the pinned Godot Android debug template: `android_debug-4.6.3.apk`,
   124546428 bytes, SHA-256
   `5cd4cfc1a8fc23ed45be5f0a36a6cc279d15b50a40c6ef69c89276895441cd1d`.
   The existing archive validator needs this file to compare engine payloads.
   The template can be supplied from an already verified dependency. For the
   approved-input-only path below, the exact local build evidence is reused and
   this template is not downloaded or revalidated; no new build is required.
4. JDK `keytool` and Android Build Tools `zipalign`/`apksigner` supporting the
   existing 16 KiB alignment and v2/v3 signing commands. Use approved tool
   versions and exact paths; no software is downloaded by this candidate.

The source-only signer does not recreate imported `.ctex` or compiled Godot
payloads. It retains the existing structural/archive checks, while the exact
approved unsigned APK hash binds the locally validated opaque payloads. It
does not claim native GPU/art approval or a remote repeat of local tests.

## Credential boundary

The repository is public at audited main commit
`31a097f032a49375467197705883287167a91aad`, whose tree has no workflow.
Configured GitHub secret names and values remain UNKNOWN. The environment
names below are an interface, not a claim that matching Secrets exist:

- `KEYSTORE_PATH`: runner-local JKS or PKCS12 file supplied by approved GitHub custody.
- `KEYSTORE_PASSWORD_FILE`: runner-local password file.
- Optional `KEY_PASSWORD_FILE`: only when a distinct key password is required.
- Optional `KEY_ALIAS`: must match the public identity if supplied.

The runner files must be owner-only and outside the checkout. The signer only
stats credential files; `keytool` and `apksigner` consume the approved paths.
Password values must not be passed as plaintext environment variables,
arguments, repository content, artifacts, or logs. Never put the keystore or
password files into the public repository or a source/artifact bundle.

One unresolved credential/setup action remains: confirm the intended existing
GitHub signing-secret mapping and its public certificate/alias; if that identity
is not configured, obtain the required action-time approval for new persistent
credential setup. The user enters/transmits any private key or password through
the approved secure handoff, never chat or this local workspace, before the
public pin is finalized. No existing secret is asserted missing, and this task
does not create, inspect, transmit, or configure keys, passwords, tokens, or
persistent access.

## Signing and return checks

After independent review and input/credential setup, the future signing call is
`python tools/build/sign_android.py --github-new-dev --development-validation
--input <approved-unsigned.apk> --output <new-signed.apk> --template <pinned-template.apk>
--expected-input-sha256 <local-report-sha256>
--expected-source-sha256 <local-report-source_sha256>`.

The signer checks approved input/source hashes and package/template integrity,
exports only the public certificate for a pre-sign fingerprint match, aligns,
signs, then requires exactly one matching APK certificate. It rechecks archive
and alignment, confirms the unsigned input did not change, and writes a new APK
plus its adjacent `.apk.signing.json` receipt. New-policy receipts include the
policy, identity ID, repository, source/template/input/output hashes, public
certificate fingerprint, package/version and unchanged development markers.

The future workflow must consume the fixed trusted source and approved input
hashes, expose credentials only to the signing process, and return only the
signed APK and receipt through an approved usable channel. Verify returned APK
bytes/hash/certificate before delivery. Artifact storage availability and the
transfer path are not established here; no artifact upload quota is assumed.
No workflow was drafted because secret mapping and input/output transport are
unresolved. No Actions run, signing, remote publication, or final delivery has
occurred in this candidate.

## Reuse the locally verified unsigned input without a template download

`--verified-input-only` is available only with `--github-new-dev` and
`--development-validation`; both approved input and staged-source SHA-256
arguments remain mandatory. This route permits omitting `--template`. It
reuses the local build's template/resource validation rather than repeating it.

The signer checks the fixed input hash and current staged-source fingerprint,
validates package/version, rejects signed inputs, duplicate/unsafe/encrypted ZIP
entries and v1 signatures, and fingerprints every decompressed entry. After
alignment and signing it verifies the certificate and alignment, requires the
v2/v3 container block, and compares the complete entry-name/hash map against
the approved input. An added, removed, renamed, or changed payload entry blocks
publication. The input hash is checked again before output publication.

This receipt explicitly records `template_revalidated=false`,
`payload_identity=matched`, and the payload entry count. Its pinned
`template_sha256` describes the reused local build dependency and does not claim
a new remote template comparison. The APK is not rebuilt for this path.
