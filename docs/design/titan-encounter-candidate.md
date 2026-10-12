# Two distinct titan encounters

Implementation candidate. Numeric values are initial playtest tuning. Neither new art identity is approved or complete; no new art or audio was generated and no anime frames/audio were extracted.

## Source and adaptation boundary

The anime production committee's official [titan glossary](https://shingeki.tv/final/keyword/) describes the Cart Titan as quadrupedal and enduring, and Zeke's Beast Titan as having long arms used for long-range throwing. These are the verified reference traits. The two ordinary-enemy roles below adapt those visual/behavioral ideas for the expansion. Their damage, timing, charge distance, frequency and stone behavior are game design choices, not claims about canonical abilities, identities or the events of year 845.

The existing runner, brute, sweeper and bosses already have distinct legacy attacks; grabber alone previously used the checked attack model. This change preserves those enemies and adds two checked roles. It does not claim that an ID list or changed statistics alone completes enemy variety.

## Combat and silhouette contract

### quadruped / 사족 질주 거인

- Art identity: `titan_quadruped`, unfinished. Low, elongated torso; head projects forward; four planted limbs. It must be distinguishable from upright runner at mobile gameplay size without reading a label.
- Suggested visual treatment: warm ochre/rust hide, low head, broad forward forelimbs. Ground-contact anchor stays centered on the 18 px body radius. The 36 px damage corridor comes from the real swept body, not sprite width guessed during rendering.
- Ordinary locomotion: exactly two readable alternating support poses are sufficient. Reuse existing valid assets elsewhere; do not spend this task rebuilding ordinary walk cycles.
- Specific attack: 54 ticks crouched warning with locked corridor, 32 ticks of straight body travel at 330 px/s (176 px maximum), then 84 ticks exposed recovery; 105 ticks cooldown. Trigger range 170 px. A lateral move avoids the locked path; chasing it straight back is less reliable.
- The body is clipped by actual walls. The warning's first legal travel cap remains fixed through saving, loading and destruction of the original wall, so removal cannot teleport the body forward.

### stone_thrower / 투석 거인

- Art identity: `titan_stone_thrower`, unfinished. Tall hunch, exaggerated long forearms, visible held stone above one shoulder. Its upright throwing silhouette must be distinct from the quadruped and ordinary walker.
- Suggested visual treatment: dark brown shoulder/arm mass, lighter torso, neutral gray stone. Body ground anchor uses radius 24 px; rock radius is 7 px.
- Ordinary locomotion: two walking poses. Additional work is limited to the telegraphed held-stone pose and readable forward release; final art is not part of this code candidate.
- Specific attack: 66 ticks shoulder-back warning, 54-tick straight rock flight at 360 px/s (324 px maximum), then 90 ticks exposed recovery; 150 ticks cooldown. Trigger range 300 px. The actor stays planted while the rock travels separately. Move sideways or use a real wall.
- Damage uses the per-tick swept rock segment. It cannot hit through walls or continue after its first collision; destroying the original blocker cannot resurrect the rock. The rock has one player-hit ledger per attack.

All ticks above are active 60 Hz simulation ticks. Pause cannot consume warning or recovery time.

## Rendering handoff

Both new attacks publish existing `phase`, actor `position`, `telegraph_geometry` and `damage_geometry` fields through `enemy_attack_view`. Render warning geometry from that packet, and do not infer damaging reach from sprite size.

The thrower additionally supplies `projectile_pose` with `previous`, `current`, `radius`, `visible` and `blocked`. Draw the moving rock only while `visible` is true. A `blocked` packet can produce an impact cue but must not draw or apply a continuing projectile. This is derived presentation data, never another damage authority or a new saved projectile.

The existing grabber still supplies `hand_pose`. Consumers must accept role-specific optional pose fields rather than assuming every role has a hand.

## Director and attack admission

Production waves keep their existing count/caps and seeded positions. The first quadruped appears after 60 s, alone among walkers for 10 s; the first thrower appears after 120 s with a similar introduction. Later every fourth eligible wave selects each new role for the first slot, retaining the old roster in other slots. This is a pacing candidate, not a completed full-run balance pass.

The checked model remains the sole admission authority for the three live roles. Existing legacy attacks contribute one two-slot observed reservation per source, not separate charges for both body and hazard. A new legacy windup cannot steal slots already reserved by live attacks. Roles waiting at least 60 ticks share one global 30-of-120-tick admission opportunity; already accepted attacks finish normally. That opportunity is bounded so geometry-rejected roles cannot stop legacy attacks forever. Legacy-only combat is unchanged.

## Save compatibility

- Run schema remains version 2. No top-level, entity or attack-instance save fields are added.
- New roles reuse the existing `role_hand_reach` scalar as the immutable first-warning travel cap. Its historical name is retained for save compatibility; validation uses the active role's maximum path length.
- `enemy_roles.1` retains the exact original six-role catalog. The extended shipped catalog is `enemy_roles.2`. Both validate under catalog schema 1, while unknown or missing IDs for their revision fail validation.
- Changed enemy definitions and manifest change the content fingerprint. Existing active runs from different content remain incompatible under the existing content-mismatch recovery flow. This candidate does not modify profile currency, permanent unlocks, purchases, or profile schema. The app must clearly explain active-run incompatibility while retaining the existing profile-preservation behavior.
- The frozen Source24 boundary snapshot and historical finite fixture files remain byte-identical. Boundary continuation tests explicitly verify all old enemy definitions, then rebind only the test copy’s enemy catalog and content fingerprints to current content. This is a current-content rebound boundary regression, not a claim that the original checkpoint is compatible. A separate Controller test feeds the unaltered historical checkpoint through real startup and verifies content mismatch, the safe keep default, an explicit preserved-new-run choice, and unchanged authority bytes.
- A missing terrain page is an explicit failed/rolled-back tick, never an empty collision world. Cold restore and origin rebase reproduce actual pose, cap, phase and one-hit identity.

## Verification limits

Headless tests cover actual Core and generated-city paths; they do not establish touchscreen feel, final art quality, Android frame time or a rendered enemy's readability. Art approval, rendering integration, user-visible content mismatch messaging and integrated Android validation remain separate work.

## Integration cautions

The asset manifest and Android development readiness currently describe five previously blocked art identities using titan_basic placeholders. They do not yet register the two new unfinished art identities. Rendering integration must label their incompleteness honestly, and export validation needs an explicit decision about those missing identities before any Android-ready claim.

The bounded legacy-yield helper scans current actors/reservations on eligible legacy action starts. Candidate-admission logical work is bounded and tested; that helper scan is not represented in the admission-work counter. Mixed dense Android frame time still needs measurement after integration.
