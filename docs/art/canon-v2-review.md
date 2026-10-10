# Shiganshina art canon review, revision 2

## User correction

2026-10-10 art-direction correction:
“거인이 왜 옷을 입고 있어. 진격의 거인 고증 철저히 지켜라”

The original ten regular/miniboss sheets incorrectly included ragged clothing. This was rejected, and the project was marked to stop final use. Revision 2 edits the original image sheets rather than painting over a black region. Successfully revised Titans have continuous natural skin, nonsexual combat poses and simplified genderless anatomy. These are original gameplay variants of mindless Titans, not claims to depict named canon individuals.

## Official references inspected

- [Season-one official glossary](https://shingeki.tv/season1/yougo/): Titan categories, Armored Titan's hard body surface, Garrison duties, standard ODM harness, ultrahard steel blades and wall-mounted cannons.
- [Official ordinary Titan image](https://shingeki.tv/season1/yougo/image/img_kyojin.jpg): skin, human-like body and disproportionate limbs.
- [Official Armored Titan image](https://shingeki.tv/season1/yougo/image/img_yoroi.jpg): pale body armor as natural hardened surface, not clothing.
- [Official Garrison image](https://shingeki.tv/season1/yougo/image/img_chutonheidan.jpg): early uniform/equipment context.
- [Official ODM reference](https://shingeki.tv/season1/yougo/image/img_rittaikidousouchi.jpg): waist/thigh harness and paired hip-mounted apparatus.
- [Official episode two](https://shingeki.tv/season1/story/episode_02.php): Shiganshina collapse story context.

These were visual/research references only. No official screenshot or extracted sprite is in a game asset. Small pixel-art insignia and anatomy are stylized abstractions; the remaining five rejected characters are not approved by this review.

## Published revision-2 entries

- titan_basic: unclothed connected body; clean-shaven, unnerving human face rather than caveman beard.
- titan_brute: unclothed heavy body, smooth simplified lower torso.
- titan_grabber: unclothed long-limbed body, no waist cord.
- boss_sweeper: unclothed oversized-forearm body, no ragged shorts.
- boss_grabber: unclothed elongated adult body, no belt or wraps.
- garrison_01: paired rose patch instead of white cross, clean-edged segmented blades instead of saw teeth, early ODM harness/gear.
- armored_titan: organic matte hardened plates and red muscle joins, revised faceplate. No death animation; final threat remains undefeated.

All retain their runtime stable IDs and use versioned PNG paths. Sources and actual-size sprites were inspected. The seven-sheet structural regression has 137 checks; the whole manifest has 41,600 checks and Godot decoding has 852 checks with no failures.

## Blocked edits, not complete

Revised source art is unavailable for these five designs:

- titan_runner: revision unavailable
- titan_sweeper: revision unavailable
- boss_charger: revision unavailable
- boss_leaper: revision unavailable
- boss_abnormal: revision unavailable

These designs are not complete. Their existing wrong-clothing entries are explicitly export-blocked while their source files remain retained for provenance. Final APK export must fail while any such record exists.

## Preview delivery

The five successful revised Titans have a native PNG plus movement GIF preview dated 2026-10-10. Those previews contain only the revised three regular and two miniboss designs. Garrison and Armored revision-2 previews are preserved with their source art.

## Handoff boundaries

Runtime art is authoritative in assets/manifest.json. Game renderer and export guard changes belong to integration. Original sources, rejected drafts and previews must stay out of APK inclusion. No external copyrighted game sprite extraction, official music or sampled soundtrack was used.

## Export safeguard verified

At 2026-10-10 07:06 UTC, The historical validation record reports an actual Android export attempt listed exactly the five blocked IDs, exited with code 3, and created no APK. Combined automatic checks were 2,545 with zero failures. The remaining art block is explicit, not treated as completed by those tests.
