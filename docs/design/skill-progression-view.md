# Skill progression view contract

`game/progression/progression_view.gd:build(state)` is a detached, read-only projection. It consumes no random draws and does not change, persist, choose, or repair the run state. The Controller presents it only when the run identity, `view_revision`, or focused offer changes.

## Authoritative flow

1. `UpgradeCatalog` reads equipment/passive definitions and the `EvolutionCatalog`. Each weapon and passive is bounded at level 5; equipment and passive slots are each bounded at 4.
2. Core earns FIFO offer descriptors through actual level-ups or boss rewards. `GrowthOfferService.materialize` produces up to three legal options and prioritizes ready evolutions. A selected target recipe can guide every even level-up.
3. UI submits the original `offer_id` and `option_id`. `RunSimulation.choose_upgrade` validates a private candidate, applies the choice once, consumes the offer, promotes the next descriptor, and validates the result. Stale/duplicate IDs, missing prerequisites, and level overflow are rejected.
4. Controller `apply_upgrade` saves the candidate before adopting it or publishing success. A failed write keeps the previous authority and the pending choice for the existing retry path.
5. An evolution keeps the original equipment slot and level 5, records `evolutions[base_item_id]`, and consumes one earned tactical seal. No new UI-owned progression state is introduced.
6. `_auto_attack` uses the catalog and selected evolution. `EvolvedAttackResolver.reserve` creates complete two-stage records, `_execute_player_attacks` executes each stage, and `_hit_entity` applies damage once per stage/target.
7. `snapshot` retains equipment/passive levels, evolution identity, cooldowns, offer identity/focus, RNG, and pending attack stages. `restore` validates prerequisites, derived offer decorations, complete pending casts, and frozen stage tuning before resuming.

## View DTO

Existing fields remain `view_revision`, `slots`, `target`, `evolutions`, and `active_offer`. The added `owned` field has `equipment` and `passives` arrays, sorted by item ID. Each row contains:

- `item_id`, `name`: canonical base item identity and authored name.
- `level`, `max_level`, `is_max`: actual level, catalog cap, and cap status.
- `evolution_id`: the associated recipe ID, even before evolving; empty when there is no recipe.
- `evolution_status`: `collecting`, `ready`, `blocked`, `evolved`, or `unavailable`, directly from recipe evaluation.
- `is_evolved`: true only after the evolution is applied. A maximum base level does not imply evolution.
- `requirements`: copied recipe requirements, each with `kind`, `item_id`, `name`, `current`, `required`, `met`, and `blocked_reason`.
- `attack_summary`: readable actual attack behavior and cooldown in seconds; passive rows use their authored description.
- `effect_stats`: current runtime-catalog values. Ordinary weapons use `weapon_stats`; combos additionally expose `total_damage = damage * hits`. Evolved weapons use recipe `effect_delta` (`stages`, `stage_damage`, `stage_delays`, `radius`, `cooldown_ticks`, plus shape-specific fields). Passive rows expose `{stat, value}` including the correct doctrine/base value.

The display name of an evolved form comes from the existing `evolutions` array matching `evolution_id`. The HUD should retain base progress and show ultimate status separately. Refresh/load is synchronization, not evidence of a newly earned level or evolution. Toasts must be based on a successful action or an in-run authoritative change, not merely first presentation of restored state.

## Existing ultimate variants

- `blade_slash` level 5 + `movement` level 3 + one tactical seal unlocks `evo_wing_cut` (입체기동 연속참). It performs two narrower sector attacks at 0 and 12 ticks, with a locked direction. The second origin follows the player's position at execution. Authored damage multipliers are 0.75 and 1.0, radius 88, arc 110°, cooldown 48 ticks, with applicable passive modifiers.
- `wall_cannon` level 5 + `fire_interval` level 3 + one tactical seal unlocks `evo_crossfire` (교차 포격 지휘). It replaces the flying shell with two fixed target-offset circular strikes at 36 and 66 ticks. Authored damage multipliers are 0.7/0.7, radius 56, acquisition range 456, point offset ±24, cooldown 168 ticks, with applicable passive modifiers. With the required fire-interval level 3, effective cooldown is 128 ticks.

## Combat presentation events

`player_attack` payloads include `attack_id`, `cast_id`, `base_item_id`, `evolution_id`, `phase` (`scheduled` or `executed`), `attack_started_tick`, `execute_tick`, `stage_index`, `stage_count`, `origin_binding`, `origin`, `direction`, `shape`, `radius`, `arc_degrees`, `damage`, `pose_tag`, and a copied `geometry` object. Shape-specific line/projectile/target fields are included when relevant.

Use `scheduled` only for anticipation; actual cast feedback follows `executed`. A `damage` event from a weapon includes `target_id`, `source_id`, `base_item_id`, `attack_id`, `amount`, and remaining `hp`. Player contact/hazard damage events share the event type and may lack weapon fields, so inspect optional fields before using them. `armor_blocked` carries zero damage and must not show a successful damaging hit. `projectile_impact` carries the projectile ID, attack ID, base item ID, impact position, and splash radius. Presentation must not apply damage or create new attacks.

## Compatibility

This change adds only derived view data. It does not change gameplay catalogs, content fingerprints, save schemas, saved offers, player career data, world/navigation behavior, or existing attack timing. Existing frozen fixtures and prior saves retain their authority and validation rules.
