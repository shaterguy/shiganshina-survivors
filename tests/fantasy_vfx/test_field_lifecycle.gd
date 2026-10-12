extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Earned = preload("res://tests/fantasy_skills/test_actual_ultimate_flow.gd")
const Director = preload("res://game/presentation/combat_vfx_director.gd")
const Bridge = preload("res://game/presentation/combat_vfx_bridge.gd")
# Detect cast-level/evolution leakage, unsafe field cap, scheduled-only effects,
# fake hit feedback, double rebase and absent-current-cast recovery.
func run(t) -> void:
	_mixed_casts(t)
	_capacity_pause_and_miss(t)
	_rebase_bridge(t)
func _mixed_casts(t) -> void:
	var sim = X.simulation()
	var state: Dictionary = Earned.new()._evolve(t,sim,"evo_inferno_zone")
	if state.is_empty(): return
	var old_record := {}
	for record in state.player_attack_instances:
		if record.base_item_id == "fire_zone" and record.evolution_id == "": old_record = record.duplicate(true); break
	t.check(not old_record.is_empty(),"actual ultimate selection leaves an already executing base fire field")
	if old_record.is_empty(): return
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("mixed-inferno",[100,0],"brute")])
	var snapshot: Dictionary = sim.snapshot(state)
	var d := Director.new()
	d.consume(events,snapshot)
	var fields := _fields(d.present(snapshot))
	t.check(fields.size() == 2,"old base cast and new ultimate cast coexist as exactly two ground fields")
	var old := fields.filter(func(e): return e.cast_id == old_record.cast_id)
	var evolved := fields.filter(func(e): return e.evolution_id == "evo_inferno_zone")
	t.check(old.size() == 1 and evolved.size() == 1,"floor grouping uses cast ID, never current equipped evolution")
	if old.size() != 1 or evolved.size() != 1: return
	t.check(old[0].art_id == "vfx_fire_zone" and old[0].cast_level == old_record.cast_level and old[0].geometry.radius == old_record.radius,"base floor retains its frozen art, level and range after evolution")
	t.check(evolved[0].art_id == "vfx_inferno_zone" and evolved[0].animation_duration_ticks == 20 and old[0].animation_duration_ticks == 30,"old and evolved area rhythms remain distinct")
	var cold: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(snapshot)))
	t.check(cold.get("ok",false),"both actual cast identities cold restore together")
	if cold.get("ok",false):
		var fresh := Director.new()
		t.check(_fields(fresh.present(sim.snapshot(cold.state))) == fields,"cold restore recovers both floors without replacing the old art")
func _capacity_pause_and_miss(t) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {"fire_zone":5}
	var d := Director.new(null,{"effect_capacity":1,"critical_reserve":400})
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("cap-target",[100,0],"brute")])
	d.consume(events,sim.snapshot(state))
	state.player.attack_ready_ticks.fire_zone = state.active_tick
	events = F.step(sim,state,Vector2.ZERO)
	d.consume(events,sim.snapshot(state))
	state.player.attack_ready_ticks.fire_zone = state.active_tick
	events = F.step(sim,state,Vector2.ZERO)
	var deferred := events.filter(func(e): return e.type == "player_attack_deferred")
	t.check(deferred.size() == 1,"real Core refuses a third simultaneous fire field")
	var snapshot: Dictionary = sim.snapshot(state)
	d.consume(events,snapshot)
	var shown := d.present(snapshot)
	t.check(_fields(shown).size() == 2 and state.player_attack_instances.size() <= 64,"critical field bodies survive reduction within two-field/shared64 budget")
	t.check(not shown.any(func(e): return e.start_tick == snapshot.active_tick),"deferred admission never creates fake contact")
	var cost: Dictionary = d.debug_stats()
	t.check(cost.effect_count <= cost.hard_capacity and cost.capacity_valid,"field pool stays within declared hard capacity")
	sim.set_pause(state,"user",true)
	var paused: Dictionary = sim.snapshot(state)
	var frozen := d.present(paused)
	for i in 10:
		t.check(F.step(sim,state,Vector2.ZERO).is_empty(),"paused Core emits no future fire hit")
		t.check(d.present(sim.snapshot(state)) == frozen,"paused floor stays at exact active-clock phase")
	sim.set_pause(state,"user",false)
	# Move the living target out of the locked field before the next real pulse.
	state.entities[0].position = [900,900]
	state.player.attack_ready_ticks.fire_zone = 999999
	while state.active_tick < 31:
		events = F.step(sim,state,Vector2.ZERO)
		d.consume(events,sim.snapshot(state))
	var missed := events.filter(func(e): return e.type == "player_attack" and e.payload.phase == "executed")
	t.check(not missed.is_empty() and not events.any(func(e): return e.type == "damage" and e.payload.get("source_id") == "fire_zone"),"real fixed-origin pulse can miss without fabricated damage")
	var current := d.present(sim.snapshot(state))
	t.check(current.any(func(e): return e.role == "cast") and not current.any(func(e): return e.recipe_id == "damage.hit_spark"),"miss shows its actual pulse and floor without fake hit spark")
func _rebase_bridge(t) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {"fire_zone":1,"chain_lightning":1}
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("rebase-target",[100,0],"brute")])
	var snapshot: Dictionary = sim.snapshot(state)
	# Coordinate-arrangement fixture only: retain actual Core events, geometry,
	# and stages, then model the streamed-origin snapshot address translation.
	snapshot.world = {"mode":"streamed_city","stage":"city","origin_chunk":["0","0"],"origin_revision":0}
	var bridge := Bridge.new()
	t.check(bridge.consume(events,snapshot),"Bridge accepts exact successful Core tick batch")
	bridge.present(snapshot)
	var old := bridge._director.present(snapshot)
	var shifted: Dictionary = snapshot.duplicate(true)
	shifted.world.origin_chunk = ["1","0"]
	shifted.world.origin_revision = 1
	shifted.player.position[0] -= 768
	for entity in shifted.entities: entity.position[0] -= 768
	for record in shifted.player_attack_instances: record.origin[0] -= 768
	bridge.present(shifted)
	var next := bridge._director.present(shifted)
	t.check(next.size() == old.size(),"one origin shift retains actual link/pulse/field population")
	for before in old:
		if before.get("coordinate_space") != "world": continue
		var after := next.filter(func(e): return e.effect_id == before.effect_id)
		t.check(after.size() == 1 and after[0].origin == before.origin-Vector2(768,0),"rebase translates each cached or reconstructed effect once")
	bridge.present(shifted)
	t.check(bridge.debug_stats().rebase_count == 1 and bridge._director.present(shifted) == next,"same-origin replay never rebases floor or link twice")
	var cold := Bridge.new()
	cold.present(shifted)
	t.check(_fields(cold._director.present(shifted)) == _fields(next),"cold origin initialization uses restored local coordinates without double subtracting")
	bridge.reset()
	t.check(bridge._director.debug_stats().effect_count == 0,"explicit bridge reset clears transient presentation state")
func _fields(values: Array) -> Array:
	return values.filter(func(e): return e.role == "area")
