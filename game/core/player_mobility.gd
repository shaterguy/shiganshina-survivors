class_name PlayerMobility
extends RefCounted
# Pure ground-plane proposals; Core alone publishes movement and applies damage.
const Address = preload("res://game/world/world_address.gd")
const Codec = preload("res://game/world/world_delta_codec.gd")
const Planner = preload("res://game/world/mobility_anchor_query.gd")
const Legacy = preload("res://game/core/legacy_player_mobility_v1.gd")
const MAX_COUNTER := 2147483647
const SPEED := 480.0
const STEP := SPEED/60.0
const DAMAGE := 12.0
const WIDTH := 20.0
const COOLDOWN := 120
const FIELDS := ["schema_version","cast_id","phase","started_tick","travel_ticks","progress","direction","path","anchors","landing","hit_ids","cooldown_until","cancelled","cancel_ticks","roll","speed","damage","width"]
const ANCHOR_FIELDS := ["prop_id","slot_id","definition_id","kind","chunk","local","connection","roof_height","pass_range","content_fingerprint","geometry_revision"]
static func initial() -> Dictionary:
	return {"schema_version":2,"cast_id":0,"phase":"ground","started_tick":0,"travel_ticks":0,"progress":0.0,"direction":[0.0,0.0],"path":[],"anchors":[],"landing":{},"hit_ids":[],"cooldown_until":0,"cancelled":false,"cancel_ticks":0,"roll":0,"speed":SPEED,"damage":DAMAGE,"width":WIDTH}
static func advance(state: Dictionary, move: Vector2, helper) -> Dictionary:
	var position := vec(state.player.position)
	var current: Dictionary = state.player_mobility
	if current.schema_version != 2: return _refused({"error_code":"mobility_migration_required"})
	var next: Dictionary = current.duplicate(true)
	var tick := int(state.active_tick)
	var moving := is_finite(move.x) and is_finite(move.y) and move.length_squared() > 0.000001
	if current.phase == "ground":
		if not moving or tick < int(current.cooldown_until): return _proposal("ground",position,next,[])
		# A pure seed/tick/cast draw can screen expensive geometry without any
		# RNG consumption or changing which eligible ticks activate.
		var roll := activation_value(int(state.seed),tick,int(current.cast_id))
		if float(roll)/4294967296.0 >= 1.0-pow(0.25,1.0/60.0): return _proposal("ground",position,next,[])
		var planned: Dictionary = Planner.plan(state,move,helper)
		if not planned.get("ok",false):
			if planned.get("error_code") == "no_mobility_path": return _proposal("ground",position,next,[])
			return _refused(planned)
		if int(current.cast_id) >= MAX_COUNTER or tick > MAX_COUNTER-COOLDOWN: return _refused({"error_code":"counter_exhausted"})
		next.cast_id = int(current.cast_id)+1
		next.phase = "boost"
		next.started_tick = tick
		next.travel_ticks = 0
		next.progress = 0.0
		next.direction = planned.direction.duplicate()
		next.path = planned.path.duplicate(true)
		next.anchors = planned.anchors.duplicate(true)
		next.landing = planned.landing.duplicate(true)
		next.hit_ids = []
		next.cooldown_until = tick+COOLDOWN
		next.roll = roll
	if not moving or move.normalized().dot(vec(next.direction)) < 0.0: return _proposal("accepted",position,grounded(next),[])
	var fresh: Dictionary = helper.mobility_pair_check(state,next.anchors)
	if not fresh.get("ok",false):
		if fresh.get("error_code") == "stale_mobility_anchor": return _proposal("accepted",position,grounded(next),[])
		return _refused(fresh)
	var route := route_sample(next,state.world.origin_chunk)
	if not route.get("ok",false): return _refused(route)
	var finish := minf(float(next.progress)+STEP,float(route.distances[1]))
	var target: Vector2 = route.points[1] if finish == float(route.distances[1]) else route.points[0]+vec(next.direction)*finish
	var checked: Dictionary = helper.sweep(position,target-position,8.0)
	if not checked.get("ok",false): return _refused(checked)
	if float(checked.fraction) < 1.0: return _proposal("accepted",position,grounded(next),[])
	var sweeps := [{"from":position,"to":checked.position}]
	next.progress = finish
	next.travel_ticks = int(next.travel_ticks)+1
	if finish >= float(route.distances[1]): next.phase = "ground"
	return _proposal("accepted",checked.position,next,sweeps)
static func activation_value(seed: int, tick: int, cast_id: int) -> int:
	return Legacy.activation_value(seed,tick,cast_id)
static func grounded(value: Dictionary) -> Dictionary:
	var result := initial()
	for field in ["cast_id","started_tick","cooldown_until","roll","hit_ids"]: result[field] = value[field].duplicate() if value[field] is Array else value[field]
	return result
static func route_sample(mobility: Dictionary, origin: Array) -> Dictionary:
	if mobility.get("schema_version") == 1: return Legacy.route_sample(mobility,origin)
	var points: Array[Vector2] = []
	for point in mobility.path:
		var relative := Address.relative(point.chunk,vec(point.local),origin)
		if not relative.get("ok",false): return relative
		points.append(relative.local)
	if points.size() != 2: return {"ok":false,"error_code":"invalid_mobility_path"}
	return {"ok":true,"points":points,"distances":[0.0,points[0].distance_to(points[1])]}
static func visual_sample(snapshot: Dictionary) -> Dictionary:
	var result := {"height":0.0,"anchors":[],"anchor":{},"roof_prop_id":"","ground_position":snapshot.get("player",{}).get("position",[0.0,0.0]).duplicate(),"phase":"ground"}
	if not snapshot.get("player_mobility") is Dictionary: return result
	var m: Dictionary = snapshot.player_mobility
	if not integer(m.get("schema_version")) or m.schema_version != 2 or not m.get("phase") is String or m.phase != "boost": return result
	result.phase = "boost"
	result.anchors = m.anchors.duplicate(true)
	return result
static func migrate_legacy(state: Dictionary, helper, ground_query := Callable()) -> Dictionary:
	if not state.has("player_mobility") or state.player_mobility.schema_version != 1: return {"ok":true}
	# Caller has already admitted every v1 field, physical route and unrelated
	# subsystem, then canonicalized vectors. Never repair invalid input here.
	var m: Dictionary = state.player_mobility
	var choices: Array[Vector2] = [vec(state.player.position)]
	if not m.path.is_empty():
		var route := Legacy.route_sample(m,state.world.origin_chunk)
		if not route.get("ok",false): return route
		choices.append(route.points[0]); choices.append(route.points[3])
	for position in choices:
		var checked: Dictionary = ground_query.call(position) if ground_query.is_valid() else helper.walkable(position,8.0)
		if not checked.get("ok",false): return checked
		if not checked.get("walkable",false): continue
		state.player.position = [position.x,position.y]
		state.player.velocity = [0.0,0.0]
		state.player_mobility = grounded(m)
		return {"ok":true}
	return {"ok":false,"error_code":"mobility_migration_no_safe_point"}
static func validate(snapshot: Dictionary, check_clock := true) -> Array[String]:
	if not snapshot.has("player_mobility"): return []
	if not snapshot.player_mobility is Dictionary: return ["invalid_player_mobility"]
	var m: Dictionary = snapshot.player_mobility
	# Validate Variant types before equality: Godot operand errors otherwise
	# abort this typed function with an empty error array (fail-open).
	if not integer(m.get("schema_version")): return ["invalid_player_mobility"]
	if not snapshot.get("world") is Dictionary or not snapshot.world.get("stage") is String or not snapshot.world.get("content_fingerprint") is String: return ["invalid_player_mobility"]
	if m.schema_version == 1:
		# Preserve the legacy contract, but reject its formerly unsafe mixed-
		# Variant revision comparison before entering admission-only code.
		if not m.get("path") is Array: return ["invalid_player_mobility"]
		for point in m.path:
			if not point is Dictionary or not point.get("geometry_revision") is String: return ["invalid_player_mobility"]
		return Legacy.validate(snapshot,check_clock)
	if not Codec.exact_keys(m,FIELDS): return ["invalid_player_mobility"]
	for field in ["schema_version","cast_id","started_tick","travel_ticks","cooldown_until","cancel_ticks"]:
		if not integer(m[field]): return ["invalid_player_mobility"]
	if m.schema_version != 2 or not m.phase is String or not m.phase in ["ground","boost"] or not m.cancelled is bool or m.cancelled or m.cancel_ticks != 0: return ["invalid_player_mobility"]
	for field in ["progress","speed","damage","width"]:
		if not number(m[field]): return ["invalid_player_mobility"]
	if not number(m.roll) or m.roll != floor(float(m.roll)) or m.roll > 4294967295: return ["invalid_player_mobility"]
	if m.speed != SPEED or m.damage != DAMAGE or m.width != WIDTH or not vector(m.direction): return ["invalid_player_mobility"]
	if not m.path is Array or not m.anchors is Array or not m.landing is Dictionary or not m.hit_ids is Array or m.hit_ids.size() > 512: return ["invalid_player_mobility"]
	var seen := {}
	for id in m.hit_ids:
		if not id is String or id.is_empty() or id.length() > 256 or seen.has(id): return ["invalid_player_mobility"]
		seen[id] = true
	if not snapshot.get("world") is Dictionary or not snapshot.world.get("origin_chunk") is Array or not snapshot.get("player") is Dictionary or not vector(snapshot.player.get("position")) or not integer(snapshot.get("active_tick")) or not integer(snapshot.get("seed")): return ["invalid_player_mobility"]
	if m.started_tick > snapshot.active_tick: return ["invalid_player_mobility"]
	if m.cast_id == 0:
		if not same(m,initial()): return ["invalid_player_mobility"]
	elif m.cooldown_until != m.started_tick+COOLDOWN or m.roll != activation_value(int(snapshot.seed),int(m.started_tick),int(m.cast_id)-1) or float(m.roll)/4294967296.0 >= 1.0-pow(0.25,1.0/60.0): return ["invalid_player_mobility"]
	if m.phase == "ground":
		if m.progress != 0 or m.travel_ticks != 0 or not m.path.is_empty() or not m.anchors.is_empty() or not m.landing.is_empty() or vec(m.direction) != Vector2.ZERO: return ["invalid_player_mobility"]
		return []
	if snapshot.world.get("stage") != "city" or m.cast_id < 1 or m.path.size() != 2 or m.anchors.size() != 2 or m.travel_ticks < 1 or m.travel_ticks > 40: return ["invalid_player_mobility"]
	if check_clock and int(snapshot.active_tick)-int(m.started_tick)+1 != int(m.travel_ticks): return ["invalid_player_mobility"]
	if absf(vec(m.direction).length_squared()-1.0) > 0.000001: return ["invalid_player_mobility"]
	var anchor_ids := {}
	for anchor in m.anchors:
		if not anchor is Dictionary or not Codec.exact_keys(anchor,ANCHOR_FIELDS): return ["invalid_player_mobility"]
		for field in ["prop_id","slot_id","definition_id","kind","content_fingerprint","geometry_revision"]:
			if not anchor[field] is String or anchor[field].is_empty(): return ["invalid_player_mobility"]
		if anchor_ids.has(anchor.prop_id): return ["invalid_player_mobility"]
		anchor_ids[anchor.prop_id] = true
		if not anchor.kind in ["roof","tree"] or not Codec.valid_hash(anchor.geometry_revision) or anchor.content_fingerprint != snapshot.world.get("content_fingerprint") or not number(anchor.roof_height) or anchor.roof_height < 16 or anchor.roof_height > 256: return ["invalid_player_mobility"]
		if not address(anchor.chunk,anchor.local) or not vector(anchor.connection) or not anchor.pass_range is Array or anchor.pass_range.size() != 4: return ["invalid_player_mobility"]
		for component in anchor.pass_range:
			if not number(component,-768.0) or component > 768: return ["invalid_player_mobility"]
		if anchor.pass_range[2] <= 0 or anchor.pass_range[3] <= 0: return ["invalid_player_mobility"]
	var revision := Planner.pair_revision(m.anchors)
	for point in m.path:
		if not point is Dictionary or not Codec.exact_keys(point,["chunk","local","height","geometry_revision"]) or not address(point.get("chunk"),point.get("local")) or not number(point.get("height")) or point.height != 0 or not point.get("geometry_revision") is String or point.geometry_revision != revision: return ["invalid_player_mobility"]
	if not same(m.landing,m.path[1]): return ["invalid_player_mobility"]
	var route := route_sample(m,snapshot.world.origin_chunk)
	if not route.get("ok",false): return ["invalid_player_mobility"]
	if route.distances[1] < 16 or route.distances[1] > 320.0002 or route.points[1].distance_to(route.points[0]+vec(m.direction)*float(route.distances[1])) > 0.0002: return ["invalid_player_mobility"]
	var alongs := []
	for index in 2:
		var relative := Address.relative(m.anchors[index].chunk,vec(m.anchors[index].local),snapshot.world.origin_chunk)
		if not relative.get("ok",false): return ["invalid_player_mobility"]
		var offset: Vector2 = relative.local-route.points[0]
		var along := offset.dot(vec(m.direction))
		var side := vec(m.direction).cross(offset)
		if along < 0 or along > route.distances[1] or offset.length() > 320.0002 or absf(side) <= 8.0 or absf(side) > Planner.SIDE_REACH or (index == 0 and side >= 0) or (index == 1 and side <= 0): return ["invalid_player_mobility"]
		alongs.append(along)
	if absf(alongs[0]-alongs[1]) > 128.0: return ["invalid_player_mobility"]
	if m.progress <= 0 or m.progress >= route.distances[1] or absf(float(m.progress)-int(m.travel_ticks)*STEP) > 0.0001: return ["invalid_player_mobility"]
	if vec(snapshot.player.position).distance_to(route.points[0]+vec(m.direction)*float(m.progress)) > 0.0002: return ["invalid_player_mobility"]
	return []
static func integer(value: Variant) -> bool:
	return number(value) and value == floor(float(value)) and value <= MAX_COUNTER
static func number(value: Variant, minimum := 0.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum
static func vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and number(value[0],-49152.0) and number(value[1],-49152.0) and absf(float(value[0])) <= 49152.0 and absf(float(value[1])) <= 49152.0
static func address(chunk: Variant, local: Variant) -> bool:
	if not chunk is Array or not vector(local): return false
	var normalized := Address.normalize(chunk,vec(local))
	return normalized.get("ok",false) and normalized.chunk == chunk and normalized.local == vec(local)
static func same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not same(a[index],b[index]): return false
		return true
	if (a is float or a is int) and (b is float or b is int): return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b
static func vec(value: Array) -> Vector2: return Vector2(float(value[0]),float(value[1]))
static func _proposal(status: String, position: Vector2, mobility: Dictionary, sweeps: Array) -> Dictionary:
	return {"status":status,"proposed_position":position,"mobility":mobility,"sweeps":sweeps}
static func _refused(result: Dictionary) -> Dictionary:
	return {"status":"refused","error_code":result.get("error_code","invalid_mobility_path")}
