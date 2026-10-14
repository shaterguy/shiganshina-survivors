class_name LegacyPlayerMobilityV1
extends RefCounted
# Admission-only v1 validation. No legacy movement or damage entry point.
const Address = preload("res://game/world/world_address.gd")
const Codec = preload("res://game/world/world_delta_codec.gd")
const MAX_COUNTER := 2147483647
const SPEED := 480.0
const STEP := SPEED/60.0
const DAMAGE := 12.0
const WIDTH := 20.0
const COOLDOWN := 120
const CANCEL_TICKS := 6
const FIELDS := ["schema_version","cast_id","phase","started_tick","travel_ticks","progress","direction","path","anchor","landing","hit_ids","cooldown_until","cancelled","cancel_ticks","roll","speed","damage","width"]
const ANCHOR_FIELDS := ["prop_id","slot_id","definition_id","kind","chunk","local","connection","roof_height","pass_range","content_fingerprint","geometry_revision","pass_start","pass_end"]
static func initial() -> Dictionary:
	return {"schema_version":1,"cast_id":0,"phase":"ground","started_tick":0,"travel_ticks":0,"progress":0.0,"direction":[0.0,0.0],"path":[],"anchor":{},"landing":{},"hit_ids":[],"cooldown_until":0,"cancelled":false,"cancel_ticks":0,"roll":0,"speed":SPEED,"damage":DAMAGE,"width":WIDTH}
static func activation_value(seed: int, tick: int, cast_id: int) -> int:
	# Preserve the exact32-bit draw, not a JSON-rounded probability fraction.
	return ("player_mobility:v1|%d|%d|%d" % [seed,tick,cast_id]).sha256_text().left(8).hex_to_int()
static func route_sample(mobility: Dictionary, origin: Array) -> Dictionary:
	var points: Array[Vector2] = []
	for point in mobility.path:
		var relative := Address.relative(point.chunk,vec(point.local),origin)
		if not relative.get("ok",false): return relative
		points.append(relative.local)
	if points.size() != 4: return {"ok":false,"error_code":"invalid_mobility_path"}
	var distances := [0.0,points[0].distance_to(points[1]),points[0].distance_to(points[2]),points[0].distance_to(points[3])]
	return {"ok":true,"points":points,"distances":distances,"glide_end":minf(16.0,float(distances[1])*0.5)}
static func phase_at(route: Dictionary, progress: float) -> String:
	if progress >= route.distances[3]: return "ground"
	if progress < route.glide_end: return "glide"
	if progress < route.distances[1]: return "rise"
	if progress <= route.distances[2]: return "over"
	return "land"
static func height_at(mobility: Dictionary, route: Dictionary, progress: float) -> float:
	var roof := float(mobility.anchor.roof_height)
	if progress <= route.glide_end: return 0.0
	if progress < route.distances[1]: return roof*(progress-float(route.glide_end))/(float(route.distances[1])-float(route.glide_end))
	if progress <= route.distances[2]: return roof
	return roof*maxf(0.0,(float(route.distances[3])-progress)/(float(route.distances[3])-float(route.distances[2])))
static func visual_sample(snapshot: Dictionary) -> Dictionary:
	var result := {"height":0.0,"anchor":{},"roof_prop_id":"","ground_position":snapshot.get("player",{}).get("position",[0.0,0.0]).duplicate(),"phase":"ground"}
	if not snapshot.get("player_mobility") is Dictionary or not snapshot.get("world") is Dictionary: return result
	var m: Dictionary = snapshot.player_mobility
	result.phase = m.phase
	if m.phase == "ground" or m.path.is_empty(): return result
	var route := route_sample(m,snapshot.world.origin_chunk)
	if not route.get("ok",false): return result
	result.height = height_at(m,route,float(m.progress))
	if int(m.cancel_ticks) > 0: result.height *= 1.0-float(m.cancel_ticks)/CANCEL_TICKS
	if not m.cancelled and m.phase in ["rise","over"]: result.anchor = m.anchor.duplicate(true)
	# Depth still belongs to this exact roof after the wire has detached.
	if m.phase == "over": result.roof_prop_id = m.anchor.prop_id
	return result
static func validate(snapshot: Dictionary, check_clock := true) -> Array[String]:
	if not snapshot.has("player_mobility"): return []
	if not snapshot.player_mobility is Dictionary: return ["invalid_player_mobility"]
	var m: Dictionary = snapshot.player_mobility
	if not Codec.exact_keys(m,FIELDS): return ["invalid_player_mobility"]
	for field in ["schema_version","cast_id","started_tick","travel_ticks","cooldown_until","cancel_ticks"]:
		if not integer(m[field]): return ["invalid_player_mobility"]
	if m.schema_version != 1 or not m.phase is String or not m.phase in ["ground","glide","rise","over","land"] or not m.cancelled is bool: return ["invalid_player_mobility"]
	for field in ["progress","speed","damage","width"]:
		if not number(m[field]): return ["invalid_player_mobility"]
	if not number(m.roll) or m.roll != floor(float(m.roll)) or m.roll > 4294967295: return ["invalid_player_mobility"]
	if m.speed != SPEED or m.damage != DAMAGE or m.width != WIDTH or not vector(m.direction): return ["invalid_player_mobility"]
	if not m.path is Array or not m.anchor is Dictionary or not m.landing is Dictionary or not m.hit_ids is Array or m.hit_ids.size() > 512: return ["invalid_player_mobility"]
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
		if m.progress != 0 or m.travel_ticks != 0 or m.cancel_ticks != 0 or m.cancelled or not m.path.is_empty() or not m.anchor.is_empty() or not m.landing.is_empty() or not m.hit_ids.is_empty() or vec(m.direction) != Vector2.ZERO: return ["invalid_player_mobility"]
		return []
	if snapshot.world.get("stage") != "city" or m.cast_id < 1 or m.path.size() != 4 or m.travel_ticks < 1 or m.travel_ticks > 40 or m.cancel_ticks >= CANCEL_TICKS: return ["invalid_player_mobility"]
	if check_clock and int(snapshot.active_tick)-int(m.started_tick)+1 != int(m.travel_ticks)+int(m.cancel_ticks): return ["invalid_player_mobility"]
	if absf(vec(m.direction).length_squared()-1.0) > 0.000001: return ["invalid_player_mobility"]
	if not Codec.exact_keys(m.anchor,ANCHOR_FIELDS): return ["invalid_player_mobility"]
	for field in ["prop_id","slot_id","definition_id","kind","content_fingerprint","geometry_revision"]:
		if not m.anchor[field] is String or m.anchor[field].is_empty(): return ["invalid_player_mobility"]
	if m.anchor.kind != "roof" or not Codec.valid_hash(m.anchor.geometry_revision) or m.anchor.content_fingerprint != snapshot.world.get("content_fingerprint") or not number(m.anchor.roof_height) or m.anchor.roof_height < 16 or m.anchor.roof_height > 256: return ["invalid_player_mobility"]
	if not address(m.anchor.chunk,m.anchor.local) or not vector(m.anchor.connection) or not m.anchor.pass_range is Array or m.anchor.pass_range.size() != 4: return ["invalid_player_mobility"]
	for component in m.anchor.pass_range:
		if not number(component,-768.0) or component > 768: return ["invalid_player_mobility"]
	if m.anchor.pass_range[2] <= 0 or m.anchor.pass_range[3] <= 0: return ["invalid_player_mobility"]
	for point in m.path:
		if not point is Dictionary or not Codec.exact_keys(point,["chunk","local","height","geometry_revision"]) or not address(point.get("chunk"),point.get("local")) or not number(point.get("height")) or point.geometry_revision != m.anchor.geometry_revision: return ["invalid_player_mobility"]
	if not same(m.anchor.pass_start,m.path[1]) or not same(m.anchor.pass_end,m.path[2]) or not same(m.landing,m.path[3]) or m.path[0].height != 0 or m.path[3].height != 0 or m.path[1].height != m.anchor.roof_height or m.path[2].height != m.anchor.roof_height: return ["invalid_player_mobility"]
	var route := route_sample(m,snapshot.world.origin_chunk)
	if not route.get("ok",false): return ["invalid_player_mobility"]
	if route.distances[1] < 1 or route.distances[2] <= route.distances[1] or route.distances[3] <= route.distances[2] or route.distances[3] > 320.0001: return ["invalid_player_mobility"]
	for index in range(1,4):
		if route.points[index].distance_to(route.points[0]+vec(m.direction)*float(route.distances[index])) > 0.0002: return ["invalid_player_mobility"]
	if m.progress <= 0 or m.progress >= route.distances[3] or absf(float(m.progress)-int(m.travel_ticks)*STEP) > 0.0001: return ["invalid_player_mobility"]
	if vec(snapshot.player.position).distance_to(route.points[0]+vec(m.direction)*float(m.progress)) > 0.0002: return ["invalid_player_mobility"]
	var expected_phase := phase_at(route,float(m.progress))
	if m.cancel_ticks > 0:
		if not m.cancelled or m.progress >= route.distances[1]: return ["invalid_player_mobility"]
		expected_phase = "land"
	if m.phase != expected_phase: return ["invalid_player_mobility"]
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
