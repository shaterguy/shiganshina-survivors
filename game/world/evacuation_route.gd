class_name EvacuationRoute
extends RefCounted
const Address = preload("res://game/world/world_address.gd")
const Navigation = preload("res://game/world/city_navigation.gd")
const Geometry = preload("res://game/combat/world_geometry.gd")
var _fixed: Dictionary
func _init(fixed_passage: Dictionary = {}) -> void:
	_fixed = fixed_passage.duplicate(true)
func select(world, player: Dictionary, origin: Array, tick: int) -> Dictionary:
	var position := _point(player.get("position",Vector2(INF,INF)))
	if player.get("hp",0) <= 0: return _error("player_dead")
	var first := _fixed.is_empty()
	var candidate: Dictionary = _fixed.duplicate(true)
	if first:
		var location := Address.normalize(origin,position)
		if not location.ok: return location
		candidate = {"passage_id":"passage:city_v1:%s:%s" % [location.chunk[0],location.chunk[1]],"chunk":location.chunk,"selected_tick":tick}
	if not candidate.get("chunk") is Array or not Address.parse(candidate.chunk).ok: return _error("invalid_passage")
	var local := Address.relative(candidate.chunk,Vector2(336,336),origin)
	if not local.ok: return _error("passage_outside_working_set")
	var rect := Rect2(local.local,Vector2(96,96))
	var nav = Navigation.new(world)
	var route: Dictionary = nav.direction(position,rect.get_center(),float(player.get("radius",8)),tick)
	if not route.ok: return route
	if first and route.length > 900: return _error("retreat_route_too_long")
	_fixed = candidate.duplicate(true)
	candidate.merge({"ok":true,"rect":rect,"waypoints":route.waypoints,"length":route.length},true)
	return candidate
static func dock_transition(state: Dictionary, passage: Dictionary, dock_definition: Dictionary) -> Dictionary:
	if state.get("player",{}).get("hp",0) <= 0 or state.get("phase","") == "dead": return _error("player_dead")
	var world: Dictionary = state.get("world",{})
	var command_id: String = passage.get("command_id","")
	if command_id.is_empty(): return _error("missing_transition_id")
	if world.get("stage","") == "dock":
		if world.get("evacuation",{}).get("transition_command_id","") == command_id: return {"ok":true,"idempotent":true,"candidate_world":world.duplicate(true),"player_position":_point(state.player.position),"retire_scene_id":"","retire_ids":{},"event":{}}
		return _error("already_in_dock")
	if world.get("stage","") != "city" or state.get("phase","") != "evacuation" or state.get("final_started_tick",-1) < 0 or state.final_started_tick > state.get("active_tick",0): return _error("invalid_transition_phase")
	if str(passage.get("passage_id","")).is_empty() or passage.passage_id != world.get("evacuation",{}).get("passage_id",""): return _error("wrong_passage")
	if not passage.get("rect") is Rect2 or not passage.rect.has_point(_point(state.player.position)): return _error("outside_passage")
	var geometry: Dictionary = dock_definition.get("geometry",{})
	var entry := _point(dock_definition.get("entry_position",[]))
	var escape := _rect(dock_definition.get("escape_rect",[]))
	if entry != Vector2.ZERO or escape != Rect2(-56,320,112,80) or geometry.is_empty() or not Geometry.valid(geometry): return _error("invalid_dock_definition")
	var radius: float = state.player.get("radius",8)
	if not Geometry.walkable(entry,radius,geometry): return _error("invalid_dock_entry")
	for corner in [escape.position,Vector2(escape.end.x,escape.position.y),escape.end,Vector2(escape.position.x,escape.end.y)]:
		if not Geometry.walkable(corner,radius,geometry): return _error("invalid_dock_escape")
	var navigation = Geometry.new()
	var point := entry
	var length := 0.0
	var goal := escape.get_center()
	for step in 226:
		if point.distance_to(goal) < 2: break
		var next: Vector2 = Geometry.move(point,navigation.direction(point,goal,radius,geometry)*minf(4,point.distance_to(goal)),radius,geometry)
		if next == point: return _error("blocked_dock_route")
		length += point.distance_to(next)
		point = next
	if point.distance_to(goal) >= 2 or length > 900: return _error("dock_route_too_long")
	var candidate := world.duplicate(true)
	candidate.stage = "dock"
	candidate.scene_id = dock_definition.get("scene_id","authored_dock")
	candidate.origin_chunk = ["0","0"]
	candidate.origin_revision = int(world.get("origin_revision",0))+1
	candidate.evacuation = world.get("evacuation",{}).duplicate(true)
	candidate.evacuation.passage_id = passage.get("passage_id","")
	candidate.evacuation.transition_command_id = command_id
	candidate.evacuation.transition_tick = state.active_tick
	candidate.escape_rect = [-56,320,112,80]
	var retire := {}
	for collection in ["entities","projectiles","telegraphs","drops","pending_attacks","pending_evolutions","player_attack_instances","enemy_attack_instances"]:
		var ids: Array = []
		for item in state.get(collection,[]): ids.append(item.get("id",item.get("attack_instance_id",item.get("attack_id",item.get("entity_id","")))))
		retire[collection] = ids
	return {"ok":true,"idempotent":false,"candidate_world":candidate,"player_position":entry,"retire_scene_id":world.get("scene_id","city"),"retire_ids":retire,"dock_route_length":length,"event":{"type":"world_scene_changed","from_stage":"city","to_stage":"dock","command_id":command_id,"tick":state.active_tick,"text":"선착장으로 퇴각","caption_ticks":60}}
static func escape_status(state: Dictionary, dock_definition: Dictionary) -> Dictionary:
	var alive: bool = state.get("player",{}).get("hp",0) > 0 and state.get("phase","") != "dead"
	var ready: bool = state.get("final_started_tick",-1) >= 0 and state.get("phase","") == "evacuation" and state.get("active_tick",0)-state.final_started_tick >= 4500
	var in_dock: bool = state.get("world",{}).get("stage","") == "dock"
	var rect := _rect(dock_definition.get("escape_rect",[]))
	return {"ready":ready,"win":alive and ready and in_dock and rect.has_point(_point(state.get("player",{}).get("position",[]))),"loss":not alive}
static func _point(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2: return Vector2(value[0],value[1])
	return Vector2(INF,INF)
static func _rect(value: Variant) -> Rect2:
	if value is Rect2: return value
	if value is Array and value.size() == 4: return Rect2(value[0],value[1],value[2],value[3])
	return Rect2()
static func _error(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}
