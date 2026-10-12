# Remaining normal-skill VFX candidate review

This is an isolated art handoff. No live manifest, runtime, combat timing, damage, geometry, actor, or integration file was modified. No wire asset was created. The integration owner retains registration and native-review responsibility.

## Observed offline raster results

All five original 1774×887 transparent PNGs were directly viewed. All five packed 1× and 4× sheets were directly viewed, including the first small 32×32 pair before continuing the second batch. These are static offline observations, not an actual game/native render review. Therefore native_reviewed, final_art_approved, and vfx_approved all remain false.

- Dash cross tip: first frame is a clear diagonal X in a 32×32 cell. It decays to a compact last-frame glint. First-frame opaque box is [3,3,28,28].
- Ally gas swoop: separated twin light tips and a thin cool teal/slate trail remain distinguishable at 32×32. It is not a round cannonball. First-frame opaque box is [1,11,30,21].
- Dash compressed gas: long parallel pressure ribbons occupy 128×32 with left anchor [0,16]. First-frame opaque box is [0,6,123,27]. The sprite does not move the actor or invent a wire.
- Reentry triple: all three cutting axes are visible together in frame 0 and throughout their decay. First-frame opaque box is [12,12,121,118]. There are no new staged hits. The source first frame extends below the nominal half-sheet line, so the two source rows are separated at y=500 through an actually transparent gap rather than cutting it at y=444. All eight source frames are retained without silhouette clipping.
- Ally arrival cut: paired tapering streaks meet at the registered center [64,64], forming a right-pointing V. First-frame opaque box is [10,35,65,92]. Its visible silhouette occupies the left side of the frame so that the actual contact point, rather than the bounding-box center, stays at the gameplay pivot.

## Remaining visible limitations

1. The approved project 24-color palette has only muted cool colors. The source teal maps to pale slate/blue-gray and silver maps to cream-white. The silhouettes remain different, but these are less saturated than the original images.
2. Cross-tip frames 5–7 are sparse at 32×32. Review them in the real 10-tick playback; no timing was changed to compensate.
3. The gas origin remains bright in the final frame. The end of the 10-tick effect may feel abrupt and needs an actual playback review.
4. Reentry frame 4 has 596 visible pixels after frame 3's 481, a small tail-size rebound. It does not introduce new directions, but the dissolve is not perfectly monotonic.
5. Arrival's V silhouette may read as a directional chevron at small rendered scale. It is unlike the cannon effect, but the double-blade reading needs review in actual zero-splash rendering.
6. Transparent source gutters contain tiny alpha-1/2 noise in some rows. The explicitly authorized uniform 50% alpha threshold removes it. All original bytes are preserved. Threshold loss and source/packed pixel counts are reported per frame; zero clipping does not mean zero downsampling loss.

## Validation and scope

The focused verifier checks all five source SHA values; eight distinct nonblank frames each; exact cells, bounds, anchors, frame order, and false approval gates; binary alpha; existing palette membership; byte-identical atlas/frame reproduction; and zero boundary clipping or geometry masking. It does not claim gameplay readability, timing, performance, or native approval.

Run from this candidate project:

    python tools/art/vfx_remaining/verify_remaining.py

The source prompts, untouched source images, palette, settings, mechanical packer, snapshot of the five requirements, and machine-readable audits are included. `manifest-additions-candidate.json` contains only the five candidate assets for additive review. Animation fields follow the existing metadata convention; runtime duration and projectile loop remain governed by the unchanged combat recipes.

Preview convention: each `*-native-left-4x-right.png` places the native-size full sheet on the left and its nearest-neighbor 4× comparison on the right. The separate `*-nearest-1x.png` and `*-nearest-4x.png` files are also supplied.
