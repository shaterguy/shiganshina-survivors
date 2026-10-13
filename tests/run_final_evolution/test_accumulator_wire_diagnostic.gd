extends RefCounted
# Observe the existing save-store numeric wire contract without any file I/O.
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const F = preload("res://tests/progression/progression_test_fixture.gd")
func run(t) -> void:
	var catalog := Catalog.new()
	var state := F.state()
	state.equipment = {"fire_zone":5}
	state.rules.allowed_equipment_ids = catalog.equipment.keys()
	var weapon: Dictionary = catalog.weapon_stats(state,"fire_zone",5)
	t.check(not weapon.is_empty(),"numeric wire diagnostic uses a legal current fire weapon")
	if weapon.is_empty(): return
	var base: float = weapon.damage
	var multiplier: float = catalog.evolutions.definition("evo_inferno_zone").effect_params.damage_multipliers[0]
	var damage := base*multiplier
	var raw := {"damage_dealt":0.0+damage}
	var wire := JSON.stringify(raw,"",true,true)
	var parsed: Dictionary = JSON.parse_string(wire)
	var store := Save.new("user://unused_final_accumulator_wire_diagnostic",Callable())
	print("FINAL_ACCUMULATOR_WIRE_DIAGNOSTIC ",JSON.stringify({"base":String.num(base,17),"multiplier":String.num(multiplier,17),"live_damage":String.num(damage,17),"wire":wire,"parsed_damage":String.num(float(parsed.damage_dealt),17),"reserialized":JSON.stringify(parsed,"",true,true),"raw_equal":raw == parsed,"store_same":store._same(raw,parsed)}))
	t.check(store._same(raw,parsed),"actual save-store contract recognizes its read-normalized damage accumulator")
	var forged := parsed.duplicate(true)
	forged.damage_dealt += 0.000001
	t.check(not store._same(raw,forged),"wire normalization does not permit an invented damage accumulator")
