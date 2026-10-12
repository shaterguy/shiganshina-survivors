# Permanent upgrades

The existing supply-credit wallet is the only currency. The UI may display it as gold. Gold comes from the existing end-of-run kill, survival, miniboss and clear settlement; this change does not add field coin drops or paid currency.

Three initial tuning candidates have five levels each, with next-level prices 20, 35, 55, 80 and 110:
- `permanent_might`: +5 percentage points to the damage multiplier per level
- `permanent_vitality`: +10 maximum HP per level
- `permanent_magnet`: +10 pickup radius per level

`profile.permanent_upgrades` is optional. Missing means no purchased levels. Existing profile fields, wallet, receipts, career ID, clear history and unlocked characters remain untouched. A purchase atomically stores its debit, new level and receipt through the existing Store revision transaction. A new run takes a deep-copied optional `run_config.permanent_upgrades`; this never adds an in-run passive or XP level, and purchases remain blocked during an unsettled run.

## Compatibility

The three additive definitions live in `SupplyCatalog.PERMANENT_ITEMS`. The original `data/supply_shop.json` bytes remain unchanged because that file belongs to the existing combat fingerprint. Adding shop-only products to that JSON would invalidate every old in-progress run and the frozen combat fixtures. Old configurations continue to produce the exact old rules dictionary. New configurations explicitly opt into permanent bonuses, and Core must derive and validate those rules from their saved levels.

Published prices and increments must not be changed in place: historical purchase receipts bind the level price, and in-progress upgraded runs bind their computed rules. A future tuning change needs an explicit historical-price/effect version or a reviewed migration rather than silently rewriting old receipts or saves. No such migration is added here.

The Store checks that new-run bonuses exactly equal purchased profile levels and rejects direct profile-level grants. Failed saves are reconciled by authoritative readback; an uncertain post-replace outcome cannot charge again with the same request ID.

## Integration

The economy layer emits `kind`, `level`, `max_level`, `current_effect_text`, `next_effect_text`, `next_price`, `is_max` and the existing purchase fields. At maximum level, `next_price` is null, `price` is 0 and the blocked reason is `max_level`.

Core integration must validate the optional config, apply HP/pickup at startup, derive `permanent_damage_bonus`, retain the config through snapshot/restore, and validate historical projectile/evolved-attack damage with the same bonus. The main-menu shop presentation and actual attack resolver integration are separate from the economy source changes.
