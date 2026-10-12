extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	var initial: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
	if initial.has("error_code"): return
	for id in ["blade_slash","chain_lightning","fire_zone","evo_wing_cut","evo_storm_chain","evo_inferno_zone"]:
		var plain := _state(sim,id,false)
		var selected := _state(sim,id,true)
		t.check(sim.restore(plain).get("ok",false) and sim.restore(selected).get("ok",false),"assembled character skill arrangement is accepted before cast: "+id)
		var base: String = Catalog.new().evolutions.definition(id).get("base_item_id",id)
		var plain_events: Array = F.step(sim,plain,Vector2.ZERO,[F.spawn("target",[40,0],"brute")])
		var selected_events: Array = F.step(sim,selected,Vector2.ZERO,[F.spawn("target",[40,0],"brute")])
		var cooldown := int(plain.player.attack_ready_ticks.get(base,0))-int(plain.active_tick)
		var selected_cd := int(selected.player.attack_ready_ticks.get(base,0))-int(selected.active_tick)
		var expected := maxi(1,int(round(cooldown*0.85))) if base == "blade_slash" else cooldown
		t.check(cooldown > 0 and selected_cd == expected,"Mikasa .85 cooldown applies to blade and wing only; chain/fire remain authored: "+id)
		t.check(not F.types(plain_events,"player_attack").is_empty() and not F.types(selected_events,"player_attack").is_empty(),"assembled trait check exercises actual casts: "+id)
		t.check(selected.stats.damage_dealt == plain.stats.damage_dealt,"Mikasa cooldown does not change initial chain/fire/blade damage: "+id)
		t.check(sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(selected),"",true,true))).get("ok",false),"assembled selected-character reservation cold-restores: "+id)
func _state(sim,id: String,mikasa: bool) -> Dictionary:
	var recipe: Dictionary = Catalog.new().evolutions.definition(id)
	var config: Dictionary = F.run_config(1,"doctrine_standard",id if not recipe.is_empty() else "evo_wing_cut")
	if mikasa: config.character_id = "mikasa_01"
	var state: Dictionary = sim.new_run(F.chapter(),42,config)
	var base: String = recipe.get("base_item_id",id)
	state.equipment = {base:5 if not recipe.is_empty() else 1}
	if not recipe.is_empty():
		for requirement in recipe.required_passives: state.passives[requirement.passive_id] = requirement.level
		for requirement in recipe.get("required_equipment",[]):
			state.equipment[requirement.equipment_id] = requirement.level
			state.player.attack_ready_ticks[requirement.equipment_id] = 2147483647
		state.evolutions = {base:id}
		state.boss_ids_fired = ["ch01_b05"]
		state.reward_ids_claimed = ["boss:ch01_b05"]
		state.stats.minibosses_defeated = 1
		state.stats.kills = 1
		state.active_tick = 18000
		state.survival_tick = 18000
	return state
