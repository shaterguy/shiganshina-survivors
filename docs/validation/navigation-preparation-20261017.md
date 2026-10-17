# Navigation preparation: validated R01 increment

## Decision and scope

Retain this exact two-file navigation change as a validated development increment.
It is not an Android release or a claim that crowd stutter is resolved.
The parent is dev18 commit `ffd8bc90ced00e58d94547b55c52e4e18ded0eee`.
No version bump, APK build, release, main-branch replacement, world/cache rewrite,
new scheduling cadence, or cross-frame memoization is included.

Within one synchronous smoothing invocation, a conservative preparation certificate
reuses repeated safety/domain preparation. Existing ray selection/order, exact memo
keys, aliases, capacity and insertion order, query ordering, collision geometry,
waypoints, and failure paths remain unchanged. Uncovered, derived, invalid, or
unsupported cases use the original path.

Admission is limited to finite start/waypoint components with absolute value at
most 8192 and finite radius 0..32. A scalar hull expanded by radius plus one pixel
must have its complete inclusive chunk rectangle resident, with each index span
at most eight. This is conservative admission slack, not collision tolerance.
Prepared visibility retains the original arithmetic and scalar query operations.

## Exact product bytes

- `game/world/city_navigation.gd`: 15629 bytes,
  SHA-256 `b44f6b8fe2193f6f65cba6b2072daa000bb0595e1da4e7f7a0816b4a76330545`
- `game/world/streamed_navigation_view.gd`: 11543 bytes,
  SHA-256 `0700e8c775de67d84f81d9849953f4854320f2961d5bf2ba2ae13c6165308423`

The six visibility-domain test files in this change are the exact files used by
the successful focused validation. Their baseline oracle is the dev18 algorithm,
with only oracle resource/class naming adapted. Existing fixture dependencies
remain inherited unchanged from the parent.

## Actual native validation, 2026-10-17 UTC

Godot 4.6.3 Linux arm64 was used with the existing controlled test resources.
The focused run completed 22 native stages, including all parse checks,
baseline 80 cases / 2438 checks and candidate 120 cases / 2868 checks, with no
failures. All 80 common ordered case IDs, native inputs/results/full-state hashes,
query counts, coverage and cache counters matched without exclusions.

The successful candidate test fixture uses legal resident-edge chunks +8/-8.
Earlier invalid +10/-11 setup failures were corrected only in tests; explicit
uncovered +/-8192 rejection remains. Product bounds were not relaxed.

The follow-on ABBA completed eight fresh traces and eight native decodes:
moving 180 and stationary 32, each A1/B1/B2/A2, 120 measured frames per trace.
Each quartet's four traces finished before its decodes. Existing successful
focused and moving-input qualification evidence was revalidated and reused.
No fresh profiling, parse/qualification rerun, or unrelated framework was added.

All 122 native records per run and full initial/final/per-frame state, ordered
events, RNG and semantic diagnostics matched. Moving runs executed attacks on
frames 15/63/111, outgoing damage 9 events / 156 total, incoming 3 / 25.
The same core/helper/resident replacement occurred at frame 38 in all moving
legs. Stationary-32 runs had no movement, combat, or replacement flags.

All 16 process cleanup receipts passed, with no owned residual processes, and
all original source, engine, cache and prior reference preservation checks passed.
Standard error was empty. Independent data-only analysis passed 864 checks,
including all 960 timing triples, AB/BA arithmetic, pins and exposed receipts.

## Measured performance

Values below are microseconds. Whole-loop elapsed includes QA observation,
native export and yielding; it is not presented FPS.

| Condition / metric | A1 | B1 | B2 | A2 | AB improvement | BA improvement |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Moving 180 / whole loop | 14041114 | 13214587 | 13247974 | 14051219 | 5.886% | 5.717% |
| Moving 180 / Controller mean | 76865.867 | 70327.333 | 70275.592 | 76993.575 | 8.506% | 8.725% |
| Moving 180 / Controller p95 | 88086 | 80100 | 80864 | 85917 | 9.066% | 5.881% |
| Moving 180 / Controller p99 | 95527 | 88655 | 86995 | 96491 | 7.194% | 9.841% |
| Moving 180 / Controller max | 150190 | 134564 | 141539 | 151411 | 10.404% | 6.520% |
| Stationary 32 / whole loop | 3651714 | 3505722 | 3437204 | 3538839 | 3.998% | 2.872% |
| Stationary 32 / Controller mean | 13617.258 | 12811.008 | 12509.833 | 13328.758 | 5.921% | 6.144% |

Both orders improved whole-loop elapsed with nonoverlapping observed lane ranges.
Moving controller mean, p95, p99, maximum and first frame improved in both orders.
Stationary-32 controller p99 ranges overlap despite both paired improvements;
these are two repeats per lane, not confidence intervals or a significance claim.
The normal-32 BA saving is 101.635 ms, smaller than the 112.875 ms baseline-repeat
spread, so its modest gain has weaker precision than the crowded result. Tiny
presentation callbacks are mixed: the moving B2 first callback is 26 vs 18 us for
A2, and stationary B2 is 17 vs 16 us. These do not erase the whole-loop/Controller
benefit, but are retained rather than declaring every metric improved.

An earlier separate stationary-180 single A/B screen improved whole-loop elapsed
4.120% and Controller mean 63.362 -> 58.972 ms. It is a different workload and
must not be substituted for moving-180's approximately 70.3 ms candidate mean.
Moving maxima remain 134.6–141.5 ms. This is a useful, repeatable CPU improvement,
but perceptible stutter resolution, Android GPU performance, thermal behavior and
long-session performance are not established.

## Evidence identities and limits

- Focused/screen source SHA-256:
  `0d34d110e2edc58b68e3a8fdf8c5855a529feaf69928f1a66dc8e7627f5a7315`
- ABBA source SHA-256:
  `49c30c2e17ab3d5012a81885c6ac64160fe78466546510158803b8835c75b58f`
- Retrieved ABBA stdout: 150651 bytes,
  SHA-256 `aa07196012df419677d5ac93876da93034c9f4891a491c3ad2eef7d499d58d0d`
- Moving comparison: 37683 bytes,
  SHA-256 `ff2ee8abdaad1f8ad4eb955f107c2c5ad901c372bd953403dc0ffd4c3dae85e8`
- Stationary-32 comparison: 33639 bytes,
  SHA-256 `5e9f8b952965ff25b4d0eaf37711238d50f0b40e0fdf8959b169ed86a0a2c328`
- Reported phase receipt: 9034 bytes,
  SHA-256 `76145a6fbf427069bc91ecdbfb7b8bc4fc88b62896286dc030634b66e523f6f0`

Full native/trace files remain in the original test evidence store. The independent
assessment used the pinned reviewed verifier and exposed receipts; it did not
independently reread all full native payloads. Source-defined numerical types were
restored only to reconstruct original summary/comparison serialization hashes;
all values stayed exact and unresolved hash mismatches were not permitted.
The runtime intentionally records adopted=false: this later development decision
does not rewrite the historical execution receipt.

The prior separate endpoint-transaction candidate remains unadopted and is not
included here. Continue the R01 crowd-stutter work from this validated increment,
using existing evidence before choosing the next bounded behavior-preserving change.

