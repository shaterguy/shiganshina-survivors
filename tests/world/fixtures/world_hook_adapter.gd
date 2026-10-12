extends RefCounted
# Test-only executable specification. Not a RunSimulation, save validator,
# spawn director, or runtime integration. C/I must apply/review their own hooks.
static func synthetic_state() -> Dictionary:
	var bosses: Array = []
	for i in 5: bosses.append({"id":"boss"+str(i),"chunk":["9007199254741000","-9007199254741000"],"local_position":[12.0,22.0],"hp":70+i,"reward_claimed":false})
	return {"active_tick":108010,"final_started_tick":108000,"player":{"position":[790.0,200.0],"velocity":[1.0,2.0],"facing":[0.0,1.0],"hp":5},"entities":[{"id":"a","position":[800.0,210.0],"locked_origin":[810.0,220.0],"locked_target":[830.0,240.0],"locked_direction":[1.0,0.0],"next_action_tick":108050}],"projectiles":[{"id":"p","source_id":"boss0","position":[800.0,100.0],"previous_position":[780.0,100.0],"velocity":[20.0,0.0]}],"drops":[{"id":"d","position":[780.0,120.0]}],"telegraphs":[{"id":"h","origin":[810.0,200.0],"direction":[0.0,1.0]}],"player_attack_instances":[{"attack_id":"wing:1","origin":[800.0,210.0],"origin_binding":"player","execute_tick":108020,"direction":[1.0,0.0]}],"enemy_attack_instances":[{"attack_id":"strike:1","origin":[820.0,230.0],"geometry":{"origin":[820.0,230.0],"target":[830.0,240.0]},"active_from_tick":108030}],"pending_evolutions":[{"origin":[840.0,210.0],"origin_binding":"locked"}],"dormant_bosses":bosses,"escape_zone":[-56.0,320.0,112,80],"world":{"origin_chunk":["9007199254740993","-9007199254740993"],"origin_revision":7,"delta_root":{"format_revision":1,"root_hash":"unchanged-root-fixture"},"evacuation":{"passage_chunk":["9007199254740993","-9007199254740993"],"passage_rect":[800.0,300.0,96,96],"entry_rect":[800.0,320.0,20,20],"route_points":[[800.0,300.0],[820.0,330.0]]}}}
static func rebase(state: Dictionary, offset: Vector2, new_origin: Array) -> Dictionary:
	var result := state.duplicate(true)
	_translate_record(result.player,["position"],offset)
	for collection in ["entities","projectiles","drops","telegraphs","player_attack_instances","enemy_attack_instances","pending_evolutions"]:
		for record in result.get(collection,[]):
			_translate_record(record,["position","previous_position","origin","locked_origin","locked_target","target","landing_target"],offset)
			if record.has("geometry"): _translate_record(record.geometry,["position","origin","target","center"],offset)
	if result.has("escape_zone"): result.escape_zone = _shift(result.escape_zone,offset)
	var evacuation: Dictionary = result.world.get("evacuation",{})
	for field in ["passage_rect","entry_rect","escape_rect"]:
		if evacuation.has(field): evacuation[field] = _shift(evacuation[field],offset)
	for i in evacuation.get("route_points",[]).size(): evacuation.route_points[i] = _shift(evacuation.route_points[i],offset)
	result.world.origin_chunk = new_origin.duplicate()
	result.world.origin_revision += 1
	return {"ok":true,"state":result,"event":{"type":"world_rebased","offset":[offset.x,offset.y],"origin_revision":result.world.origin_revision}}
static func validate_command(command: Dictionary, revision: int) -> Dictionary:
	return {"ok":command.get("origin_revision",-1) == revision,"error_code":"" if command.get("origin_revision",-1) == revision else "stale_origin_revision"}
static func _translate_record(record: Dictionary, fields: Array, offset: Vector2) -> void:
	for field in fields:
		if record.has(field): record[field] = _shift(record[field],offset)
static func _shift(value: Array, offset: Vector2) -> Array:
	var shifted := value.duplicate()
	shifted[0] = float(value[0])-offset.x
	shifted[1] = float(value[1])-offset.y
	return shifted
static func spawn_fixture() -> Dictionary:
	return {"visibility_policy":"conservative_fixed_envelope","visibility_rect":Rect2(-200,-300,400,600),"player_position":Vector2.ZERO,"notice_margin":192,"minimum_separation":256,"candidates":[{"id":"safe","position":Vector2(1000,384),"radius":32,"walkable":true,"connected_route":true},{"id":"visible","position":Vector2(0,100),"radius":32,"walkable":true,"connected_route":true},{"id":"solid","position":Vector2(1000,384),"radius":32,"walkable":false,"connected_route":true},{"id":"disconnected","position":Vector2(1000,384),"radius":32,"walkable":true,"connected_route":false}]}
static func spawn_allowed(candidate: Dictionary, fixture: Dictionary) -> bool:
	return candidate.walkable and candidate.connected_route and candidate.position.distance_to(fixture.player_position) >= fixture.minimum_separation and not fixture.visibility_rect.grow(fixture.notice_margin+candidate.radius).has_point(candidate.position)
static func defer_spawn(id: String) -> Dictionary:
	return {"deferred":true,"entity_id":id}
static func retirement_allowed(render_bounds: Rect2, visibility_rect: Rect2) -> bool:
	return not render_bounds.intersects(visibility_rect,true)
