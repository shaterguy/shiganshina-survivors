extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
const Catalog = preload("res://game/economy/supply_catalog.gd")
const Service = preload("res://game/economy/supply_service.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
func run(t) -> void:
	var sim = Core.new(Current.new())
	var legacy: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
	t.check(sim.restore(legacy).get("ok") == true and not legacy.rules.has("permanent_damage_bonus"),"Legacy run retains exact rules and restores")
	var config: Dictionary = F.run_config()
	config.permanent_upgrades = {"permanent_might":5,"permanent_vitality":2,"permanent_magnet":2}
	var state: Dictionary = sim.new_run(F.chapter(),42,config)
	t.check(not state.has("error_code"),"Real Core accepts purchased levels")
	if state.has("error_code"): return
	t.check(state.player.hp == 120 and state.player.max_hp == 120 and state.rules.base_hp == 120,"Real next run applies permanent HP")
	t.check(state.rules.pickup_radius == 50,"Real next run applies pickup radius")
	t.check(is_equal_approx(state.rules.get("permanent_damage_bonus",0.0),0.25),"Real Core derives capped attack bonus from levels")
	t.check(state.passives == legacy.passives and state.player.level == 1,"Permanent upgrade occupies no run passive or XP level")
	t.check(sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true))).get("ok") == true,"Upgraded run restores after JSON/app restart")
	var tampered := state.duplicate(true)
	tampered.rules.permanent_damage_bonus = 99.0
	t.check(sim.restore(tampered).get("ok") == false,"Invented attack bonus fails Core restore")
	tampered = state.duplicate(true)
	tampered.rules.pickup_radius = 999
	t.check(sim.restore(tampered).get("ok") == false,"Invented pickup radius fails Core restore")
	state.drops.append({"id":"probe_xp","position":[float(state.player.position[0])+40.0,float(state.player.position[1])],"xp":1})
	legacy.drops.append({"id":"probe_xp","position":[float(legacy.player.position[0])+40.0,float(legacy.player.position[1])],"xp":1})
	F.step(sim,state,Vector2.ZERO)
	F.step(sim,legacy,Vector2.ZERO)
	t.check(state.player.xp == 1 and legacy.player.xp == 0,"Permanent magnet actually collects beyond legacy radius")
	var save: Dictionary = Fixture.new().game_save()
	save.profile.supply_credits = 20
	var service = Service.new(sim.new_run)
	var bought: Dictionary = service.prepare_purchase(save,"permanent_vitality","purchase:%s:0:permanent_vitality" % save.career_id,0)
	t.check(bought.get("ok") == true,"Purchase prepares real Core start")
	if not bought.get("ok",false): return
	var started: Dictionary = service.prepare_run_start(bought.candidate,F.chapter(),17,"start:%s:1" % save.career_id,0)
	t.check(started.get("ok") == true,"Purchase-to-real-Core flow starts")
	if started.get("ok",false): t.check(started.candidate.checkpoint.player.max_hp == 110,"Bought level applies to next real run")
