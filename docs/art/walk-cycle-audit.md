# Walking-cycle audit and Armored Titan correction

## Reported defect

Reported visual defect: The Armored Titan v2 frames1–4 showed predominantly one leading leg rather than a complete alternating cycle. A structural test confirming different frame bytes did not establish valid gait; the earlier visual sign-off did not catch this.

## Scope of the audit

The following previously generated successful character movement sets were inspected as whole contact sheets:

- armored_titan v2: same near leg leads most frames; alternate contact/passing not established. Correction candidate v3b exists but has not replaced the runtime manifest.
- titan_basic v2: predominantly repeated near-leg-leading half-cycle; needs genuine opposite contact and passing.
- titan_brute v2: both limbs change apparent position somewhat, but complete repeatable left/right stance phases are not reliably readable. Needs correction.
- titan_grabber v2: near leg remains ahead throughout most movement frames; needs correction.
- boss_sweeper v2: near leg remains ahead; needs correction.
- boss_grabber v2: near leg remains ahead; needs correction.
- garrison_01 v2: six running poses vary lean/stride but the leading-leg swap is not reliably readable; needs a complete running-cycle correction.

The five blocked character designs remain unresolved. Clothing/canon correction and locomotion approval are separate gates. Correct clothing status does not mean walking quality passed.

## Armored candidate iterations

1. One-shot eight-pose sheet repeated the same leading leg and was rejected, never published.
2. Individual articulated poses were generated for opposite contact, support, passing and swing. Version3 established true leg alternation; visual review found torso-width/camera drift near phases1–3 and concern at loop8→1.
3. Version3b redraws contact and down poses against the opposite-contact design to harmonize torso/camera and strengthen the bent support knee. Existing v2 nonmovement frames0–11 retain identical visible RGB and alpha. New movement phases append at indices12–19 in a 4×5 atlas of192×256 cells; anchor remains[96,256].

Each candidate uses actual redrawn limb articulation. No old pose was merely mirrored, shifted or bobbed to fake walking. Small per-phase registration heights preserve contact/down/passing/up presentation but are not the source of the limb movement.

## Current candidate, not final approval

- `assets/art/characters/armored_titan_v3b.png`
- `assets/art/previews/Shiganshina-armored-walk-v3b-cycle.png`
- `assets/art/previews/Shiganshina-armored-walk-v3b.gif`
- Eight frames each140ms, total1120ms, infinite loop. Matching runtime rate would be7.142857fps.
- Sequence: near contact, near support/down, far early passing, far swing/up, far contact, far support/down, near passing, near swing/up.
- Actual playback, stance sliding, torso consistency and the 8→1 boundary still require review.
- Runtime manifest remains on v2 until explicit review approval. v3 and v3b are retained as review candidates, not accepted final animation.

## Structural regression

`python tests/assets/test_armored_walk_candidate.py` verifies RGBA, palette/binary alpha,20 nonempty multicolor frames,12 preserved visible frames,8 different poses, exact GIF frame delays and loop length. These checks intentionally do not claim gait correctness or smoothness.

## Contralateral-motion correction: v3c candidate

Reported visual defect: Expanded limb-chain inspection found that v3b phase3 had same-side forward arm/support leg, phase6 had drifted back into bright-leg-leading while the bright arm was forward, and phase7's arm phase was ambiguous. v3b was rejected for this gate. Three poses were redrawn; the correction changed the image pixels.

The near/brighter side is anatomical right throughout. The far/darker side is anatomical left. This assignment is held through occlusion and never swapped to make the phase table pass. RA/LA/RL/LL traces are shown in Shiganshina-armored-v3c-limb-audit.png and stored with the atlas hash in armored-v3c-limb-landmarks.json. Landmark positions are hand-inspected approximate annotation points; occluded joints are estimates, not exact measured anatomy.

| Phase | Right arm | Left arm | Right leg | Left leg | Current audit |
|---|---|---|---|---|---|
|1|Back|Forward|Forward heel contact|Back trailing|Opposed|
|2|Back|Forward|Forward loaded knee|Back lifting|Opposed|
|3|Back, before reversal|Forward, before reversal|Support near hip|Early swing, still behind|Opposed, early passing|
|4|Forward|Back|Back toe support|Forward raised knee|Opposed|
|5|Forward|Back|Back trailing|Forward heel contact|Opposed|
|6|Forward|Back|Back trailing knee|Forward loaded dark leg|Opposed; leg identity corrected|
|7|Back|Forward|Forward lifted knee|Support under hip|Opposed; arm phase corrected|
|8|Back|Forward|Forward reach|Back toe support|Opposed|

Version3c retains8×140ms =1120ms. Manifest is still v2 pending actual playback review. A valid side/phase table is necessary but not sufficient: body consistency, foot sliding, passing continuity and loop8→1 still need actual-play review. The other six previously successful character movement sets remain uncorrected; the five blocked designs were not retried.
