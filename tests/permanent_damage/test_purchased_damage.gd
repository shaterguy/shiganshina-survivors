extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Finite = preload("res://tests/core/finite_chapter_provider.gd")
const Supply = preload("res://game/economy/supply_service.gd")
const SaveFixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const View = preload("res://game/progression/progression_view.gd")
func run(t) -> void:
	_base_damage(t)
	_projectiles(t)
	for evolution in ["evo_wing_cut","evo_crossfire"]: _evolved(t,evolution)
	_summary(t)
func _bought(sim) -> Dictionary:
	var save: Dictionary = SaveFixture.new().game_save()
	save.profile.supply_credits = 20
	var service := Supply.new(sim.new_run)
	var bought := service.prepare_purchase(save,"permanent_might","purchase:%s:0:permanent_might" % save.career_id,0)
	if not bought.get("ok",false): return {}
	var started := service.prepare_run_start(bought.candidate,F.chapter(),42,"start:%s:1" % save.career_id,0)
	return started.candidate.checkpoint if started.get("ok",false) else {}
func _base_damage(t) -> void:
	var sim := Core.new(Finite.new())
	var catalog := Catalog.new()
	for item in F.EQUIPMENT_IDS:
		var state := _bought(sim)
		t.check(not state.is_empty(),"actual might purchase can start a real run")
		if state.is_empty(): return
		t.check(is_equal_approx(state.rules.permanent_damage_bonus,0.05),"purchase derives exactly one immutable five-percent run bonus")
		state.equipment = {item:5}
		state.passives = {"damage":2}
		var definition: Dictionary = catalog.equipment[item]
		var expected := (float(definition.damage)+4.0*float(definition.damage_per_level))*1.35
		t.check(is_equal_approx(catalog.weapon_stats(state,item,5).damage,expected),"permanent and run damage bonuses add exactly once: "+item)
		var view := View.new().build(state)
		t.check(is_equal_approx(view.owned.equipment[0].effect_stats.damage,expected),"owned HUD reports purchased runtime damage: "+item)
		var events := F.step(sim,state,Vector2.ZERO,[F.spawn("damage-target",[45,0],"brute")])
		var attacks := F.types(events,"player_attack")
		t.check(attacks.size() == 1,"real base cast is emitted after purchase: "+item)
		if attacks.size() == 1:
			var cast_damage: float = expected*float(definition.get("hits",1))
			t.check(is_equal_approx(attacks[0].payload.damage,cast_damage),"executed base attack matches purchased HUD value: "+item)
		t.check(sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state),"",true,true))).get("ok",false),"post-purchase base cast cold-restores: "+item)
	var maximum: Dictionary = F.run_config()
	maximum.permanent_upgrades = {"permanent_might":5}
	var max_state := sim.new_run(F.chapter(),42,maximum)
	t.check(not max_state.has("error_code") and is_equal_approx(catalog.weapon_stats(max_state,"blade_slash",1).damage,15.0),"maximum purchased bonus is twenty-five percent")
	var legacy := sim.new_run(F.chapter(),42,F.run_config())
	t.check(catalog.weapon_stats(legacy,"blade_slash",1).damage == 12.0 and not legacy.rules.has("permanent_damage_bonus"),"legacy missing bonus remains exactly zero")
func _projectiles(t) -> void:
	var sim := Core.new(Finite.new())
	for item in ["wall_cannon","ally_cover"]:
		var state := _bought(sim)
		state.equipment = {item:2}
		state.passives = {"damage":1}
		var row: Dictionary = Catalog.new().equipment[item]
		var expected := (float(row.damage)+float(row.damage_per_level))*1.20
		F.step(sim,state,Vector2.ZERO,[F.spawn("flying-target",[120,0],"brute")])
		t.check(state.projectiles.size() == 1,"purchased weapon launches an actual projectile: "+item)
		if state.projectiles.is_empty(): continue
		t.check(is_equal_approx(state.projectiles[0].damage,expected),"flying projectile freezes the purchased cast damage")
		# Assert the expected contract before the validator is changed too.
		state.projectiles[0].damage = expected
		state.equipment[item] = 5
		state.passives.damage = 2
		state.player.attack_ready_ticks[item] = 2147483647
		var restored := sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
		t.check(restored.get("ok",false),"old projectile tuning with fixed purchase bonus survives later run upgrades")
		if not restored.get("ok",false): continue
		var cold := Core.new(Finite.new())
		var damage_events := []
		for tick in 30:
			var left := F.step(sim,state,Vector2.ZERO)
			var right := F.step(cold,restored.state,Vector2.ZERO)
			t.check(left == right and state == restored.state,"purchased projectile cold-replays through its actual hit")
			damage_events.append_array(F.types(left,"damage"))
		var found := false
		for event in damage_events:
			if event.payload.get("base_item_id","") == item:
				found = true
				t.check(is_equal_approx(event.payload.amount,expected),"actual projectile hit retains purchased pre-upgrade damage")
		t.check(found,"purchased projectile reaches and damages its target")
func _evolved(t,evolution: String) -> void:
	var sim := Core.new(Finite.new())
	var state := _bought(sim)
	var catalog := Catalog.new()
	var recipe: Dictionary = catalog.evolutions.definition(evolution)
	var base: String = recipe.base_item_id
	# Valid test-only already-earned boss ledger; the offer and choice are real.
	state.equipment = {base:5}
	state.passives = {recipe.required_passives[0].passive_id:3}
	state.active_tick = 18099
	state.survival_tick = 18099
	state.boss_ids_fired = ["ch01_b05"]
	state.reward_ids_claimed = ["boss:ch01_b05"]
	state.stats.minibosses_defeated = 1
	state.stats.kills = 1
	state.tactical_seals = 1
	F.drop_xp(sim,state,24,"purchased:evolution-xp")
	var choice := sim.choose_upgrade(state,state.upgrade_offer.offer_id,"evolution:"+evolution)
	t.check(choice.get("ok",false),"purchased run applies actual ready evolution offer: "+evolution)
	if not choice.get("ok",false): return
	var events := F.step(sim,state,Vector2.ZERO,[F.spawn("evolved-target",[60,0],"brute")])
	var attacks := F.types(events,"player_attack").filter(func(event): return event.payload.phase == "scheduled")
	t.check(attacks.size() == 2,"purchased ultimate reserves both stages")
	if attacks.size() != 2: return
	var definition: Dictionary = catalog.equipment[base]
	var base_damage := (float(definition.damage)+4.0*float(definition.damage_per_level))*1.05
	var owned: Dictionary = View.new().build(state).owned.equipment[0]
	for index in 2:
		var expected := base_damage*float(recipe.effect_params.damage_multipliers[index])
		t.check(is_equal_approx(attacks[index].payload.damage,expected) and is_equal_approx(owned.effect_stats.stage_damage[index],expected),"purchased evolved stage and HUD share one damage formula")
	for record in state.player_attack_instances:
		record.damage = base_damage*float(recipe.effect_params.damage_multipliers[int(record.stage_index)])
	state.player.attack_ready_ticks[base] = 2147483647
	var reserved := state.duplicate(true)
	var restored := sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(restored.get("ok",false),"pending purchased ultimate stages pass cold restore")
	if not restored.get("ok",false): return
	var forged := reserved.duplicate(true)
	forged.player_attack_instances[0].damage += 0.1
	t.check(not sim.restore(forged).get("ok",false),"purchased ultimate validation still rejects invented stage damage")
	state.passives.damage = 1
	restored.state.passives.damage = 1
	t.check(sim.restore(state).get("ok",false),"late passive upgrade preserves fixed bonus and earlier reserved damage")
	var cold := Core.new(Finite.new())
	var executed := F.types(events,"player_attack").filter(func(event): return event.payload.phase == "executed")
	for tick in int(recipe.effect_params.stage_delays[1]):
		var left := F.step(sim,state,Vector2.ZERO)
		var right := F.step(cold,restored.state,Vector2.ZERO)
		t.check(left == right and state == restored.state,"purchased ultimate replays exact stage events after cold restore")
		executed.append_array(F.types(left,"player_attack").filter(func(event): return event.payload.phase == "executed"))
	t.check(executed.size() == 2 and state.player_attack_instances.is_empty(),"purchased ultimate stages execute and retire exactly once")
	for event in executed:
		var expected := base_damage*float(recipe.effect_params.damage_multipliers[int(event.payload.stage_index)])
		t.check(is_equal_approx(event.payload.damage,expected),"execution retains purchase plus cast-time passive rather than current modifier")
func _summary(t) -> void:
	var view := View.new()
	var summary := view._attack_summary({"description":"새로운 형태의 공격"},{"is_evolved":true,"evolution_id":"evo_future","effect_stats":{"cooldown_ticks":60,"stage_delays":[0,12],"stages":2}})
	t.check(summary.contains("새로운 형태의 공격") and not summary.contains("포격"),"unknown evolution never silently describes crossfire")
