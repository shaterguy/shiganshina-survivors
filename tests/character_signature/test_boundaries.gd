extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Signature = preload("res://game/combat/character_skill_resolver.gd")
const Wall = preload("res://tests/fantasy_skills/test_actual_cover.gd")
class Counts:
	extends "res://game/combat/spatial_hash.gd"
	var calls := 0
	func query(point: Vector2, radius: float) -> Array[int]:
		calls += 1
		return super.query(point,radius)
func _config() -> Dictionary:
	var c := F.run_config()
	c.character_id = "mikasa_01"; c.character_skill_revision = 1
	return c
func _state(sim, chapter: Dictionary = {}) -> Dictionary:
	var state: Dictionary = sim.new_run(F.chapter() if chapter.is_empty() else chapter,41,_config())
	state.player.attack_ready_ticks.blade_slash = 2147483647
	return state
func _hits(events: Array) -> Array:
	return events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == Signature.TOKEN)
func run(t) -> void:
	_probe(t)
	_miss(t)
	_cover(t)
	_growth(t)
	_terminal_and_final(t)
func _probe(t) -> void:
	var sim = F.simulation(t)
	var state := _state(sim)
	var queries := Counts.new(); sim._spatial = queries
	for i in 60: F.step(sim,state,Vector2.ZERO)
	t.check(queries.calls == 10 and state.attack_seq == 0 and state.character_skill.ready_tick == 0,"ready miss probes exactly ten times per sixty active ticks with no cooldown/serial consumption")
	F.step(sim,state,Vector2.ZERO,[F.spawn("probe",[65,0],"brute")])
	t.check(queries.calls == 12 and state.player_attack_instances.size() == 2,"one acquisition plus first execution query and only two future records")
	var after: int = queries.calls
	for i in 100: F.step(sim,state,Vector2.ZERO)
	t.check(queries.calls == after+2,"cooldown adds no queries except two already scheduled strikes")
	var saturated := _state(sim)
	saturated.active_tick = 1
	for i in 62: saturated.player_attack_instances.append({"untouched":i})
	var records: Array = saturated.player_attack_instances.duplicate(true)
	var events: Array[Dictionary] = []
	queries.calls = 0
	sim._auto_signature(saturated,events)
	t.check(queries.calls == 0 and saturated.player_attack_instances == records and saturated.attack_seq == 0 and saturated.character_skill.ready_tick == 0 and saturated.character_skill.next_probe_tick == 7,"62 of64 reservations defer before query without displacing others")
	var exhausted := _state(sim)
	F.step(sim,exhausted,Vector2.ZERO,[F.spawn("counter",[65,0],"brute")])
	exhausted.player_attack_instances.clear()
	exhausted.character_skill = Signature.initial_state()
	exhausted.event_seq = 2147483647-4
	var serial: int = exhausted.attack_seq
	sim._auto_signature(exhausted,events)
	t.check(exhausted.attack_seq == serial and exhausted.player_attack_instances.is_empty(),"reservation requires event room for scheduling execution and a possible hit")
	var copied: Dictionary = sim._tick_candidate(state)
	copied.character_skill.next_probe_tick += 1
	t.check(copied.character_skill != state.character_skill,"transactional candidate detaches signature runtime dictionary")
func _miss(t) -> void:
	for mode in ["range","sector","killed","normal_first"]:
		var sim = F.simulation(t)
		var state := _state(sim)
		if mode == "normal_first": state.player.attack_ready_ticks.blade_slash = 0
		var events := F.step(sim,state,Vector2.ZERO,[F.spawn("fixed",[65,0],"brute"),F.spawn("other",[95,0],"brute")])
		if mode == "normal_first":
			# At the second strike tick, the ordinary immediate weapon executes
			# before signature stage1 and kills the fixed target.
			state.entities[0].hp = 1.0
			state.player.attack_ready_ticks.blade_slash = 9
			state.attack_seq = 9 # Existing string-ID sort puts cast10 before pending cast2.
		elif mode == "range": state.entities[0].position = [250,0]
		elif mode == "sector": state.entities[0].position = [-70,0]
		else:
			state.entities[0].hp = 0.0
			sim._remove_dead(state)
		var hits := 0
		for i in 16:
			events = F.step(sim,state,Vector2.ZERO)
			hits += _hits(events).size()
		t.check(hits == 0 and state.character_skill.pending_cast_id == "","fixed target remains a miss without retarget after "+mode)
func _cover(t) -> void:
	var provider := Wall.WallProvider.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var sim := Core.new(provider)
	var state := _state(sim,chapter)
	# Short acquisition range reaches the body across x85 wall but must not hit.
	var events := F.step(sim,state,Vector2.ZERO,[F.spawn("covered",[115,0],"brute")])
	t.check(_hits(events).is_empty() and state.character_skill.pending_cast_id == "","finite solid cover blocks signature acquisition")
	state.entities[0].position = [60,0]
	for i in 6: events = F.step(sim,state,Vector2.ZERO)
	t.check(not state.character_skill.pending_cast_id.is_empty(),"same target can be acquired on visible side")
	state.entities[0].position = [115,0]
	var hits := 0
	for i in 16: hits += _hits(F.step(sim,state,Vector2.ZERO)).size()
	t.check(hits == 0,"pending signature rechecks real finite cover at both later strikes")
func _growth(t) -> void:
	var sim = F.simulation(t)
	var state := _state(sim)
	state.equipment = {"blade_slash":5,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	state.passives = {"damage":1,"movement":5,"fire_interval":5,"attack_range":5}
	# Exhaust current run-attack final choices to isolate the later passive card.
	state.evolutions = {"blade_slash":"evo_wing_cut","spin_slash":"evo_whirlwind","odm_dash":"evo_sky_lance","reentry_combo":"evo_echo_assault"}
	for item in state.equipment: state.player.attack_ready_ticks[item] = 2147483647
	F.step(sim,state,Vector2.ZERO,[F.spawn("growth-target",[80,0],"brute")])
	var damage: float = state.player_attack_instances[0].damage
	# Real XP offer/pause and commit API changes the passive after reservation.
	F.drop_xp(sim,state,24)
	t.check(not state.upgrade_offer.is_empty(),"actual growth offer pauses pending signature")
	if state.upgrade_offer.is_empty(): return
	var before := state.duplicate(true)
	F.step(sim,state,Vector2.ZERO)
	t.check(state == before,"growth pause preserves remaining attack stages")
	var option := {}
	for row in state.upgrade_offer.options:
		if row.get("item_id") == "damage": option = row
	t.check(not option.is_empty(),"bounded full-slot fixture offers actual damage passive")
	if option.is_empty(): return
	var proposal: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,option.option_id)
	t.check(proposal.get("ok",false) and state.passives.damage == 2,"actual growth choice applies later damage passive")
	t.check(state.player_attack_instances[0].damage == damage and sim.restore(state).get("ok",false),"cast-time level remains exactly frozen after later passive growth")
func _terminal_and_final(t) -> void:
	var sim = F.simulation(t)
	var state := _state(sim)
	F.step(sim,state,Vector2.ZERO,[F.spawn("terminal",[70,0],"brute")])
	var before: Dictionary = state.character_skill.duplicate(true)
	state.phase = "dead"; state.player.hp = 0.0
	t.check(sim.restore(state).get("ok",false),"terminal checkpoint retains valid pending signature")
	var records: Array = state.player_attack_instances.duplicate(true)
	for i in 20: F.step(sim,state,Vector2.ZERO)
	t.check(state.character_skill == before and state.player_attack_instances == records,"death preserves pending ownership but cannot execute attacks")
	state = _state(sim)
	state.active_tick = 107998; state.survival_tick = 107998
	F.step(sim,state,Vector2.ZERO,[F.spawn("before-final",[70,0],"brute")])
	before = state.character_skill.duplicate(true)
	F.step(sim,state,Vector2.ZERO,[F.final_command(state)])
	t.check(state.phase == "evacuation" and state.player_attack_instances.is_empty() and state.character_skill.pending_cast_id == "","begin_evacuation discards future stages and their pointer together")
	t.check(state.character_skill.ready_tick == before.ready_tick and state.character_skill.next_probe_tick == before.next_probe_tick and sim.restore(state).get("ok",false),"begin_evacuation retains both cooldown clocks and restores cleanly")
