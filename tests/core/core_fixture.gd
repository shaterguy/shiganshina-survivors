extends RefCounted
const Loot = preload("res://game/loot/loot_rules.gd")
const EQUIPMENT_IDS := ["blade_slash", "spin_slash", "odm_dash", "reentry_combo", "wall_cannon", "ally_cover"]
static func chapter() -> Dictionary:
	return {"chapter_id":"chapter_01_shiganshina", "content_revision":"ch01.1", "spawn_position":[0.0, 0.0], "character_availability":[{"character_id":"garrison_01", "unlock_condition":"default"}], "allowed_equipment_ids":EQUIPMENT_IDS.duplicate(), "initial_equipment":{"blade_slash":1}, "progression":{"base_xp":6,"xp_per_level":4}, "enemy_catalog":{"slow_titan":{"hp":8.0,"speed":0.0,"radius":10.0,"contact_damage":10.0,"xp":2}, "test_boss":{"hp":8.0,"speed":0.0,"radius":12.0,"contact_damage":15.0,"xp":6}}}
static func simulation(t):
	var path := "res://game/core/run_simulation.gd"
	t.check(FileAccess.file_exists(path), "RunSimulation core exists")
	if not FileAccess.file_exists(path): return null
	var script = load(path)
	t.check(script != null and script.can_instantiate(), "RunSimulation compiles")
	return script.new() if script != null and script.can_instantiate() else null
static func spawn(id: String, position: Array, enemy_id := "slow_titan") -> Dictionary:
	return {"command_id":"spawn:" + id,"kind":"spawn_enemy","payload":{"entity_id":id,"enemy_id":enemy_id,"position":position,"spawned_tick":0}}
static func boss(id: String, position: Array) -> Dictionary:
	return {"command_id":"boss:" + id,"kind":"spawn_boss","payload":{"entity_id":"entity:" + id,"boss_id":id,"enemy_id":"test_boss","position":position,"scheduled_tick":18000}}
static func types(events: Array, event_type: String) -> Array:
	return events.filter(func(event): return event.type == event_type)
static func hazard(id: String, shape := "circle", extra := {}) -> Dictionary:
	var payload := {"source_id":"test","shape":shape,"origin":[0.0,0.0],"direction":[1.0,0.0],"radius":20.0,"length":50.0,"width":12.0,"warning_ticks":0,"active_ticks":1,"damage":1000.0}
	payload.merge(extra, true)
	return {"command_id":id,"kind":"telegraph_attack","payload":payload}

static func step(sim, state: Dictionary, move: Vector2, values: Array = []) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	commands.assign(values)
	return sim.step(state,move,commands)

# NEW C2/C3 real-content fixture. Historical chapter() above remains unchanged.
static func v2_chapter() -> Dictionary:
	var result: Dictionary = load("res://game/director/chapter_catalog.gd").new().load_chapter("chapter_01_shiganshina")
	return result.get("chapter",{})
static func run_config(serial: int = 1, doctrine: String = "doctrine_standard", target: String = "evo_wing_cut", supply: String = "") -> Dictionary:
	return {"run_id":"0123456789abcdef0123456789abcdef:%d"%serial,"run_serial":serial,"doctrine_id":doctrine,"target_evolution_id":target,"prepared_supply":supply}
# Test-only arranged prerequisites followed by an actual authored boss killing hit.
# This does not claim natural leveling or full-run balance. Empty means the real
# constructor/restore/spawn/reward path rejected the requested fixture.
static func evolution_ready_state(sim, chapter_data: Dictionary, config: Dictionary, seed: int = 42) -> Dictionary:
	if config.get("target_evolution_id") != "evo_wing_cut": return {}
	var state: Dictionary = sim.new_run(chapter_data,seed,config)
	if state.has("error_code"): return {}
	state.equipment = {"blade_slash":5}
	# Derive prerequisites from the selected definition, including legacy schema one.
	var recipe: Dictionary = sim._catalog.evolutions.definition("evo_wing_cut")
	for required in recipe.get("required_equipment",[]): state.equipment[required.equipment_id] = int(required.level)
	state.passives = {"movement":3}
	for required in recipe.required_passives: state.passives[required.passive_id] = int(required.level)
	if Loot.enabled(state):
		# New-rule fixture only: create due source evidence before the old clock
		# jump. A matching resident helper is required before any city query.
		# This is arranged fixture time, not evidence of natural spawn cadence.
		state.active_tick = 10800
		state.survival_tick = 10800
		var geometry_ready: bool = not state.has("world") or state.world.stage != "city"
		if not geometry_ready:
			geometry_ready = sim._streamed != null and sim._streamed.matches(state) and sim._streamed.readiness(state).get("ok",false) and sim._streamed.query_status().get("ok",false)
		if geometry_ready:
			var due_events: Array[Dictionary] = []
			sim._update_loot(state,due_events)
		else:
			# Source creation is geometry-free. Preserve pending state rather than
			# querying unrelated/unprepared city coverage or forcing placement.
			sim._add_loot(state,Loot.field_spec(0),Vector2(state.player.position[0],state.player.position[1]))
	state.active_tick = 17999
	state.survival_tick = 17999
	state.player.attack_ready_ticks = {"blade_slash":18001}
	for id in state.equipment:
		if id != "blade_slash": state.player.attack_ready_ticks[id] = 2147483647
	if not sim.restore(state).get("ok",false): return {}
	var command := {"command_id":"fixture:boss:ch01_b05","kind":"spawn_boss","payload":{"entity_id":"fixture:boss1","boss_id":"ch01_b05","enemy_id":"boss_charger","position":[45,0],"scheduled_tick":18000}}
	step(sim,state,Vector2.ZERO,[command])
	if state.entities.size() != 1: return {}
	state.entities[0].hp = 36.0
	if not sim.restore(state).get("ok",false): return {}
	step(sim,state,Vector2.ZERO)
	if Loot.enabled(state):
		# The actual lethal hit now earns a chest. Collect its actual placement
		# without a combat/XP tick, forced reward, status change or moved chest.
		var id := Loot.chest_id(state.run_id,"boss","ch01_b05")
		var chest := Loot.find_chest(state,id)
		if chest.is_empty() or chest.status not in ["placed","queued"]: return {}
		var pickup_events: Array[Dictionary] = []
		if chest.status == "placed":
			var local := Loot.local_position(state,chest)
			if not local.get("ok",false): return {}
			var player := Vector2(state.player.position[0],state.player.position[1])
			if not sim._loot_path_clear(state,player,local.position): return {}
			state.player.position = [local.position.x,local.position.y]
			sim._update_loot(state,pickup_events)
		if not sim._activate_next_offer(state,pickup_events): return {}
		if state.tactical_seals != 1 or state.stats.minibosses_defeated != 1 or state.upgrade_offer.get("source") != "chest" or state.upgrade_offer.get("chest_id") != id: return {}
	elif state.tactical_seals != 1 or state.stats.minibosses_defeated != 1 or state.upgrade_offer.get("source") != "boss": return {}
	var restored: Dictionary = sim.restore(state)
	return restored.state if restored.get("ok",false) else {}

# Test-only time arrangement for settlement/timer cases. The final physical
# action retains its remaining phase instead of manufacturing expired FSM data.
static func arrange_final_clock(state: Dictionary, tick: int) -> void:
	var offset := tick-int(state.active_tick)
	state.active_tick = tick
	for entity in state.entities:
		if entity.get("enemy_id") != "armored_titan": continue
		for field in ["action_started_tick","action_ends_tick","next_action_tick"]: entity[field] = int(entity[field])+offset
	for hazard in state.telegraphs:
		for field in ["created_tick","active_from_tick","expires_tick"]: hazard[field] = int(hazard[field])+offset
