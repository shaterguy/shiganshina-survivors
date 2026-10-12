extends RefCounted
func run(t) -> void:
	var path := "res://game/director/spawn_director.gd"
	t.check(FileAccess.file_exists(path), "SpawnDirector exists")
	if not FileAccess.file_exists(path): return
	var script = load(path)
	t.check(script != null and script.can_instantiate(), "SpawnDirector compiles")
	if script == null or not script.can_instantiate(): return
	var director = script.new()
	var chapter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://chapters/chapter_01/manifest.json"))
	var state := {"phase":"survival","pause_reasons":[],"active_tick":17999,"survival_tick":17999,"seed":7,"player":{"position":[0,0]},"entities":[],"boss_ids_fired":[],"next_entity_id":1,"final_started_tick":-1,"escape_zone":chapter.escape_zone.duplicate()}
	var before := JSON.stringify(state)
	var result: Array[Dictionary] = director.plan(state, chapter)
	t.check(result.filter(func(c): return c.kind == "spawn_boss").size() == 1, "5min boss exactly at threshold")
	t.check(JSON.stringify(state) == before, "director never mutates state")
	t.check(result == director.plan(state, chapter), "repeated plan deterministic")
	state.boss_ids_fired = ["ch01_b05"]
	t.check(director.plan(state, chapter).filter(func(c): return c.kind == "spawn_boss").is_empty(), "fired boss not rescheduled")
	state.survival_tick = 107999
	state.active_tick = 107999
	t.check(director.plan(state, chapter).filter(func(c): return c.kind == "begin_evacuation").size() == 1, "30min final threat appears")
	state.phase = "evacuation"
	state.final_started_tick = 108000
	state.active_tick = 112498
	t.check(director.plan(state, chapter).filter(func(c): return c.kind == "evacuation_ready").is_empty(), "cannot escape before75sec")
	state.active_tick = 112499
	t.check(director.plan(state, chapter).filter(func(c): return c.kind == "evacuation_ready").size() == 1, "75sec readiness threshold")
	state.pause_reasons = ["upgrade"]
	t.check(director.plan(state, chapter).is_empty(), "paused director emits nothing")
	state.pause_reasons = []
	state.phase = "survival"
	state.active_tick = 239
	state.survival_tick = 239
	state.entities = [{"id":1,"enemy_id":"boss_charger","position":[0,-100],"spawned_tick":0}]
	t.check(director.plan(state,chapter).filter(func(c): return c.kind == "telegraph_attack").is_empty(),"core alone owns actor attack timing")
	state.entities = []
	state.active_tick = 90029
	state.survival_tick = 90029
	state.boss_ids_fired = ["ch01_b05","ch01_b10","ch01_b15","ch01_b20","ch01_b25"]
	var late: Array[Dictionary] = director.plan(state,chapter)
	t.check(late.filter(func(c): return c.kind == "spawn_enemy").size() >= 6,"late waves produce a horde rather than lone spawns")
	var unique_ids: Array = []
	for command in late:
		if command.kind == "spawn_enemy" and not command.payload.entity_id in unique_ids: unique_ids.append(command.payload.entity_id)
	t.check(unique_ids.size() == late.size(),"group spawn IDs unique")
	state.entities.resize(178)
	t.check(director.plan(state,chapter).filter(func(c): return c.kind == "spawn_enemy").size() <= 2,"group wave respects180 normal actor cap")
