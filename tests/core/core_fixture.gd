extends RefCounted
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
