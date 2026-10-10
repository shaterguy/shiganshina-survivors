extends RefCounted
const ROLE_IDS := ["walker", "runner", "grabber", "sweeper", "brute", "leaper"]
static func read_catalog(t) -> Dictionary:
	var path := "res://game/combat/enemy_role_catalog.gd"
	t.check(FileAccess.file_exists(path), "role catalog module exists")
	if not FileAccess.file_exists(path): return {}
	var script = load(path)
	t.check(script != null and script.can_instantiate(), "role catalog compiles")
	if script == null or not script.can_instantiate(): return {}
	var result: Dictionary = script.read()
	t.check(result.get("ok", false), "approved role catalog reads: " + str(result.get("errors", [])))
	return result.get("catalog", {})
static func actor(enemy_id: String, position: Array = [0.0, 0.0]) -> Dictionary:
	return {"id":1, "enemy_id":enemy_id, "position":position.duplicate(), "facing":[1.0, 0.0], "radius":{"walker":18.0,"runner":16.0,"grabber":20.0,"sweeper":20.0,"brute":24.0,"leaper":20.0}.get(enemy_id,20.0)}
static func player(position: Array = [0.0, 0.0], speed: float = 150.0) -> Dictionary:
	return {"id":"player", "position":position.duplicate(), "radius":8.0, "move_speed":speed}
