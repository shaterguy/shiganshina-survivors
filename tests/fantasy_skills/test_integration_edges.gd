extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const Supplies = preload("res://game/economy/supply_catalog.gd")
const Fantasy = preload("res://game/combat/fantasy_attack_resolver.gd")
func run(t) -> void:
	var chapter: Dictionary = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
	t.check("chain_lightning" in chapter.allowed_equipment_ids and "fire_zone" in chapter.allowed_equipment_ids,"actual production chapter permits both new skills")
	t.check("evo_storm_chain" in chapter.evolution_ids and "evo_inferno_zone" in chapter.evolution_ids,"actual production chapter permits both ultimate targets")
	for level in [0,1,5,2.0]:
		var result: Dictionary = Supplies.new().permanent_levels({"permanent_upgrades":{"permanent_might":level}})
		t.check(result.get("permanent_might") is int and result.permanent_might == level,"validated permanent levels are copied as canonical integers")
	for level in [true,false,NAN,INF,-1,6,1.5,"2"]:
		t.check(Supplies.new().permanent_levels({"permanent_upgrades":{"permanent_might":level}}).is_empty(),"canonical level copy never relaxes invalid guard")
	_pause_and_capacity(t)
	_chain_bounds(t)
func _pause_and_capacity(t) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {"fire_zone":5}
	F.step(sim,state,Vector2.ZERO,[F.spawn("field-target",[100,0],"brute")])
	state.player.attack_ready_ticks.fire_zone = state.active_tick
	F.step(sim,state,Vector2.ZERO)
	state.player.attack_ready_ticks.fire_zone = state.active_tick
	var events := F.step(sim,state,Vector2.ZERO)
	var deferred := F.types(events,"player_attack_deferred")
	t.check(deferred.size() == 1 and deferred[0].payload.reason == "field_capacity","third overlapping field is explicitly refused")
	t.check(state.player_attack_instances.size() == 14,"two fire fields keep only fourteen future pulses")
	var cold: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state)))
	t.check(cold.get("ok",false),"two-field cap and retry tick cold restore")
	sim.set_pause(state,"user",true)
	var before: Dictionary = state.duplicate(true)
	for tick in 30: t.check(F.step(sim,state,Vector2.ZERO).is_empty(),"pause cannot advance fire pulses")
	t.check(state == before,"paused finite fields do not age or accumulate damage")
func _chain_bounds(t) -> void:
	var state := {"player":{"position":[0,0]},"entities":[],"evolutions":{},"active_tick":1}
	var indices := []
	for index in 512:
		indices.append(index)
		state.entities.append({"id":"e-%04d"%index,"hp":100,"radius":10,"position":[40,0]})
	var visits := [0]
	var query := func(_p,_r): visits[0] += indices.size(); return indices
	var clear := func(_a,_b): return true
	var stats := {"chain_count":12,"range":180,"hop_range":120,"damage":10}
	var records: Array = Fantasy.chain_records(state,stats,"chain_lightning","test:attack:1",query,clear)
	t.check(records.size() == 12 and visits[0] == 6144,"maximum crowd chain work is bounded by twelve queries of at most512 entities")
	var used := {}
	for record in records:
		t.check(not used.has(record.target_id),"crowded same-position target is never hit twice")
		used[record.target_id] = true
	var blocked := func(_a,_b): return false
	t.check(Fantasy.chain_records(state,stats,"chain_lightning","test:attack:2",query,blocked).is_empty(),"fully covered targets produce no fake lightning segment")
