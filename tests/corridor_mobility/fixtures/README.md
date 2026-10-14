# Genuine legacy mobility fixtures

These immutable snapshots were captured from the unmodified dev7 product source
commit 38b0cb1 before implementing v2 corridor movement. They are save-admission
fixtures, never runtime roof-flight inputs.

`legacy_ground`, `legacy_glide`, `legacy_rise`, `legacy_over`, `legacy_land` use the
existing `tests/terrain_mobility/motion_fixture.gd` Provider and normal Core steps.
`legacy_over_interior` was independently captured after further normal Core steps
inside that same actual roof, at [144,216], progress 40. The first `over` snapshot
is at the leading roof clearance boundary and is still normally walkable; restore
therefore preserves that coordinate. The interior snapshot must return to the
stored safe starting point.

Every packet contains full Core state plus exact empty-world hydration and source
provenance. Do not regenerate with the current v2 runtime. Tests validate the
original full v1 contract before expecting migration and test corrupt derivatives
without overwriting these fixtures.

`legacy_dock_ground` was independently captured through the genuine dev7
Controller dock transition at active tick 108023. Its baseline restore is valid;
v2 migration must query the original finite authored dock geometry, never the
city-only streamed helper.
