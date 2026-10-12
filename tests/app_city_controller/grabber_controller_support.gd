extends RefCounted
# Controlled encounter only. Actual Director/Core/Controller remain installed.
# Time jumps beyond the existing unlock; initial unrelated spawned actors and
# their hazards are removed; grabber is relocated onto a query-verified lane.
# Equipment/HP stay authored; automatic player attack is postponed for survival.
static func arrange(t, app) -> Dictionary:
	app.start_run(42)
	if app.state.is_empty(): return {}
	var spawn_tick := -1
	var requested_id: Variant = null
	for tick in range(28801,29401):
		var probe: Dictionary = app.state.duplicate(true)
		probe.active_tick = tick-1
		probe.survival_tick = tick-1
		for command in app.director.plan(probe,app.chapter):
			if command.kind == "spawn_enemy" and command.payload.enemy_id == "grabber":
				spawn_tick = tick
				requested_id = command.payload.entity_id
				break
		if spawn_tick >= 0: break
	t.check(spawn_tick > 28800,"unchanged Director offers grabber only in its existing post-unlock wave")
	if spawn_tick < 0: return {}
	app.state.active_tick = spawn_tick-1
	app.state.survival_tick = spawn_tick-1
	app.state.player.attack_ready_ticks.blade_slash = spawn_tick+1000
	app._last_save_tick = spawn_tick-1
	app._last_phase = app.state.phase
	app.advance_frame(1.0/60.0)
	var source: Dictionary = {}
	for entity in app.state.entities:
		if entity.id == requested_id and entity.enemy_id == "grabber": source = entity; break
	t.check(not source.is_empty() and app.simulation.step_status().ok,"actual Controller executes real Director grabber spawn command")
	if source.is_empty(): return {}
	var removed: int = app.state.entities.size()-1
	app.state.entities = [source]
	app.state.telegraphs.clear()
	app.state.enemy_attack_instances.clear()
	# Find an actual open 210px lane in the currently prepared city.
	var player := Vector2(app.state.player.position[0],app.state.player.position[1])
	var chosen := Vector2.INF
	for axis in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
		var position: Vector2 = player-axis*150.0
		var walk: Dictionary = app.simulation._streamed.walkable(position,22.0)
		var swept: Dictionary = app.simulation._streamed.sweep(position,axis*210.0,22.0)
		if walk.get("ok",false) and walk.get("walkable",false) and swept.get("ok",false) and swept.get("position",Vector2.INF).distance_to(position+axis*210.0) < 0.01:
			chosen = position
			break
	t.check(chosen.is_finite(),"controlled city lane is verified by real prepared swept geometry")
	if not chosen.is_finite(): return {}
	source.position = [chosen.x,chosen.y]
	source.velocity = [0.0,0.0]
	source.action_state = "move"
	source.action_started_tick = app.state.active_tick
	source.action_ends_tick = app.state.active_tick
	source.next_action_tick = app.state.active_tick
	source.locked_origin = source.position.duplicate()
	source.locked_target = app.state.player.position.duplicate()
	app.advance_frame(1.0/60.0)
	var packet: Dictionary = app.world._enemy_attack_packet
	t.check(packet.get("ok",false) and packet.get("attacks",[]).size() == 1,"actual Controller presents successful Core warning without a feature flag")
	if packet.get("attacks",[]).size() != 1: return {}
	return {"source_id":str(requested_id),"spawn_tick":spawn_tick,"started_tick":int(app.state.active_tick),"removed_initial_actors":removed,"torso":source.position.duplicate(),"hp":app.state.player.hp,"packet":packet.duplicate(true)}
static func at_tick(t, app, target: int) -> bool:
	while int(app.state.active_tick) < target:
		var before: int = app.state.active_tick
		app.advance_frame(1.0/60.0)
		if int(app.state.active_tick) != before+1:
			t.check(false,"actual Controller advances to requested hand boundary; error="+app._city_step_error+"/"+app._city_render_error)
			return false
	return true
