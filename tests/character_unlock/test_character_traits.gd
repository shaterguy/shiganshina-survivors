extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
func run(t) -> void:
	var sim = Core.new(Current.new())
	var chapter: Dictionary = Current.new().load_chapter("chapter_01_shiganshina").chapter
	var config := F.run_config()
	var plain: Dictionary = sim.new_run(chapter,42,config)
	config.character_id = "mikasa_01"
	var mikasa: Dictionary = sim.new_run(chapter,42,config)
	t.check(not mikasa.has("error_code") and mikasa.get("character_id") == "mikasa_01","Actual constructor accepts selected Mikasa identity")
	if mikasa.has("error_code") or mikasa.get("character_id") != "mikasa_01": return
	t.check(is_equal_approx(mikasa.rules.move_speed,plain.rules.move_speed*1.08),"Immutable character trait derives actual movement speed")
	t.check(mikasa.rules.get("character_blade_cooldown_multiplier") == 0.85,"Immutable blade trait is separate from purchased upgrades")
	var origin: float = plain.player.position[0]
	for i in 10:
		F.step(sim,plain,Vector2.RIGHT)
		F.step(sim,mikasa,Vector2.RIGHT)
	t.check(is_equal_approx(mikasa.player.position[0]-origin,(plain.player.position[0]-origin)*1.08),"Actual movement travels eight percent farther")
	var restored: Dictionary = Core.new(Current.new()).restore(JSON.parse_string(JSON.stringify(sim.snapshot(mikasa),"",true,true)))
	t.check(restored.get("ok",false) and restored.state.character_id == "mikasa_01","Cold Core JSON restore preserves character movement")
	var forged := sim.snapshot(mikasa)
	forged.rules.character_blade_cooldown_multiplier = 0.01
	t.check(not sim.restore(forged).get("ok",false),"Forged character multiplier rejects on restore")
	forged = sim.snapshot(mikasa)
	forged.character_id = "garrison_01"
	t.check(not sim.restore(forged).get("ok",false),"Run config and character identity mismatch rejects")
	var default_state: Dictionary = sim.new_run(chapter,42,F.run_config())
	var character_state: Dictionary = sim.new_run(chapter,42,config)
	F.step(sim,default_state,Vector2.ZERO,[F.spawn("target",[40,0])])
	F.step(sim,character_state,Vector2.ZERO,[F.spawn("target",[40,0])])
	var default_cd := int(default_state.player.attack_ready_ticks.get("blade_slash",0))-int(default_state.active_tick)
	var character_cd := int(character_state.player.attack_ready_ticks.get("blade_slash",0))-int(character_state.active_tick)
	t.check(default_cd > 0 and character_cd == maxi(1,int(round(default_cd*0.85))),"Actual basic blade attack reserves shorter cooldown")
	t.check(character_state.stats.damage_dealt == default_state.stats.damage_dealt,"Cooldown trait does not add weapon damage")
	for evolution in ["evo_wing_cut","evo_crossfire"]:
		var defaults: Dictionary = sim.new_run(chapter,42,F.run_config())
		var selected: Dictionary = sim.new_run(chapter,42,config)
		var base := "blade_slash" if evolution == "evo_wing_cut" else "wall_cannon"
		var recipe: Dictionary = sim._catalog.evolutions.definition(evolution)
		for state in [defaults,selected]:
			state.equipment = {base:5}
			state.passives = {"movement":3} if evolution == "evo_wing_cut" else {"fire_interval":3}
			# Keep the original modifiers on both characters and satisfy the
			# current owned-Lv1 material without adding a second attacking family.
			for required in recipe.get("required_equipment",[]):
				state.equipment[required.equipment_id] = int(required.level)
				state.player.attack_ready_ticks[required.equipment_id] = 2147483647
			for required in recipe.required_passives: state.passives[required.passive_id] = int(required.level)
			state.tactical_seals = 1-int(recipe.seal_cost)
			state.stats.minibosses_defeated = 1
			state.stats.kills = 1
			state.boss_ids_fired = ["ch01_b05"]
			state.reward_ids_claimed = ["boss:ch01_b05"]
			state.evolutions = {base:evolution}
			state.active_tick = 18000
			state.survival_tick = 18000
			state.run_config.target_evolution_id = evolution
			t.check(sim.restore(sim.snapshot(state)).get("ok",false),"Both character evolution arrangements satisfy actual recipe and seal ledger: "+evolution)
			F.step(sim,state,Vector2.ZERO,[F.spawn("evolved_target",[40,0])])
		var cooldown := int(defaults.player.attack_ready_ticks.get(base,0))-int(defaults.active_tick)
		var selected_cd := int(selected.player.attack_ready_ticks.get(base,0))-int(selected.active_tick)
		t.check(cooldown > 0 and selected_cd == (maxi(1,int(round(cooldown*0.85))) if evolution == "evo_wing_cut" else cooldown),"Actual evolved reservation applies only blade trait: "+evolution)
		t.check(sim.restore(sim.snapshot(selected)).get("ok",false),"Selected character restores actual pending evolution stage: "+evolution)
	var original := F.run_config()
	var legacy: Dictionary = sim.new_run(chapter,42,original)
	t.check(not legacy.run_config.has("character_id") and not legacy.rules.has("character_blade_cooldown_multiplier"),"Legacy absent fields remain absent")
	for invalid in ["levi_01","eren_01","unknown",123,null]:
		var bad := F.run_config()
		bad.character_id = invalid
		t.check(sim.new_run(chapter,42,bad).get("ok") == false,"Unavailable/malformed character is not playable: "+str(invalid))
