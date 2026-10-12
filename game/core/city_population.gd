class_name CityPopulation
extends RefCounted
# NEW bounded offscreen population policy. Pure planning; Core owns publication.
const Address = preload("res://game/world/world_address.gd")
const EXIT_DISTANCE := 1536.0
const ENTER_DISTANCE := 1280.0
const MAX_DORMANT_BOSSES := 5
const MAX_DROPS := 256
const MAX_LOCAL := 49152.0
# More than maximum 225 px/s travel over the signed-31-bit tick lifetime.
# Keep relative arithmetic bounded without converting absolute int64 addresses.
const MAX_DISTANCE_CHUNKS := 16777216
static func plan(state: Dictionary) -> Dictionary:
	var result := {"ok":true,"retire":[],"park_entities":[],"park_drops":[],"wake_entities":[],"wake_drops":[]}
	if not state.get("world") is Dictionary or state.world.get("stage") != "city": return result
	if not state.get("player") is Dictionary or not point_valid(state.player.get("position")): return failure("invalid_snapshot")
	var owners := {}
	for collection in ["entities","drops","telegraphs","enemy_attack_instances"]:
		if not state.get(collection) is Array or state[collection].size() > {"entities":512,"drops":256,"telegraphs":512,"enemy_attack_instances":64}[collection]: return failure("invalid_snapshot")
	for collection in ["telegraphs","enemy_attack_instances"]:
		for attack in state[collection]:
			if not attack is Dictionary: return failure("invalid_snapshot")
			owners[str(attack.get("source_id",""))] = true
	for index in state.entities.size():
		var record = state.entities[index]
		if not record is Dictionary or not point_valid(record.get("position")): return failure("invalid_snapshot")
		if not outside(state,record) or not quiescent(state,record,owners): continue
		if not record.get("boss_id") is String: continue
		if not record.boss_id.is_empty(): result.park_entities.append(index)
		else: result.retire.append(index)
	for index in state.drops.size():
		var record = state.drops[index]
		if not record is Dictionary or not point_valid(record.get("position")): return failure("invalid_snapshot")
		if outside(state,record): result.park_drops.append(index)
	if state.world.get("schema_version",1) == 2:
		if not dormant_shape(state.world.get("dormant")): return failure("invalid_snapshot")
		for pair in [["entities","wake_entities"],["drops","wake_drops"]]:
			for index in state.world.dormant[pair[0]].size():
				var entry: Dictionary = state.world.dormant[pair[0]][index]
				var distance := distance_squared(entry.chunk,entry.record.position,state.world.origin_chunk,state.player.position)
				if not distance.get("ok",false): return distance
				var localized := Address.relative(entry.chunk,vec(entry.record.position),state.world.origin_chunk)
				# Far absolute records remain dormant without asking the world to
				# invent geometry. All saved addresses were validated above.
				if localized.get("ok",false) and separation([localized.local.x,localized.local.y],state.player.position) <= ENTER_DISTANCE:
					result[pair[1]].append(index)
	return result
static func outside(state: Dictionary, record: Dictionary) -> bool:
	return separation(record.position,state.player.position) >= EXIT_DISTANCE
static func separation(a: Array, b: Array) -> float:
	return maxf(absf(float(a[0])-float(b[0])),absf(float(a[1])-float(b[1])))
static func quiescent(state: Dictionary, record: Dictionary, owners: Variant = null) -> bool:
	if record.get("action_state") != "move" or not record.has("id"): return false
	if owners is Dictionary: return not owners.has(str(record.id))
	for collection in ["telegraphs","enemy_attack_instances"]:
		for attack in state.get(collection,[]):
			if not attack is Dictionary: return false
			if str(attack.get("source_id","")) == str(record.id): return false
	return true
static func dormant_shape(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or not value.has_all(["entities","drops"]): return false
	for pair in [["entities",MAX_DORMANT_BOSSES],["drops",MAX_DROPS]]:
		if not value[pair[0]] is Array or value[pair[0]].size() > pair[1]: return false
		for entry in value[pair[0]]:
			if not entry is Dictionary or entry.size() != 2 or not entry.has_all(["chunk","record"]): return false
			if not entry.chunk is Array or not Address.parse(entry.chunk).get("ok",false) or not entry.record is Dictionary or not point_valid(entry.record.get("position")): return false
			for component in entry.record.position:
				if float(component) < 0 or float(component) >= Address.CHUNK_SIZE: return false
	return true
static func distance_squared(a_chunk: Array, a_local: Array, b_chunk: Array, b_local: Array) -> Dictionary:
	if not point_valid(a_local) or not point_valid(b_local): return failure("invalid_snapshot")
	var a := Address.parse(a_chunk)
	var b := Address.parse(b_chunk)
	if not a.get("ok",false) or not b.get("ok",false): return failure("invalid_chunk_address")
	var dx := _difference(a.x,b.x)
	var dy := _difference(a.y,b.y)
	if not dx.get("ok",false) or not dy.get("ok",false): return failure("address_overflow")
	if dx.value < -MAX_DISTANCE_CHUNKS or dx.value > MAX_DISTANCE_CHUNKS or dy.value < -MAX_DISTANCE_CHUNKS or dy.value > MAX_DISTANCE_CHUNKS: return failure("invalid_snapshot")
	# Do not convert absolute chunk addresses to float: adjacent chunks beyond
	# 2^53 must remain distinct. No Vector2 float32 distance arithmetic here.
	var x := float(dx.value)*Address.CHUNK_SIZE+float(a_local[0])-float(b_local[0])
	var y := float(dy.value)*Address.CHUNK_SIZE+float(a_local[1])-float(b_local[1])
	var squared := x*x+y*y
	return {"ok":true,"value":squared} if is_finite(squared) else failure("invalid_snapshot")
static func _difference(a: int, b: int) -> Dictionary:
	if (b > 0 and a < Address.MIN_INT+b) or (b < 0 and a > Address.MAX_INT+b): return failure("address_overflow")
	return {"ok":true,"value":a-b}
static func point_valid(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for scalar in value:
		if not (scalar is int or scalar is float) or not is_finite(float(scalar)) or absf(float(scalar)) > MAX_LOCAL: return false
	return true
static func vec(value: Array) -> Vector2: return Vector2(float(value[0]),float(value[1]))
static func failure(code: String) -> Dictionary: return {"ok":false,"error_code":code}

const POSITION_FIELDS := ["position","previous_position","origin","target","locked_origin","locked_target","landing_target"]
static func apply_to_candidate(state: Dictionary) -> Dictionary:
	var changes := plan(state)
	if not changes.get("ok",false): return changes
	var changed := false
	for field in ["retire","park_entities","park_drops","wake_entities","wake_drops"]:
		if not changes[field].is_empty(): changed = true
	if not changed: return {"ok":true,"changed":false,"retired":0,"retired_entity_ids":[],"woken_entities":[]}
	var world_changed: bool = not changes.park_entities.is_empty() or not changes.park_drops.is_empty() or not changes.wake_entities.is_empty() or not changes.wake_drops.is_empty()
	var world: Dictionary = state.world.duplicate(true) if world_changed else state.world
	if world_changed and int(world.schema_version) == 1:
		world.schema_version = 2
		world.dormant = {"entities":[],"drops":[]}
	var entities := []
	var retired_entity_ids := []
	var drops := []
	for pair in [["entities",entities],["drops",drops]]:
		var collection: String = pair[0]
		var active: Array = pair[1]
		for index in state[collection].size():
			if collection == "entities" and index in changes.retire:
				retired_entity_ids.append(state.entities[index].id)
				continue
			var record: Dictionary = state[collection][index]
			if index in changes["park_"+collection]:
				var normalized := Address.normalize(state.world.origin_chunk,vec(record.position))
				if not normalized.get("ok",false): return normalized
				var parked := translate_record(record,-normalized.offset)
				if not parked.get("ok",false): return parked
				world.dormant[collection].append({"chunk":normalized.chunk,"record":parked.record})
			else: active.append(record)
	var woken_entities := []
	if world_changed:
		for pair in [["entities",entities],["drops",drops]]:
			var collection: String = pair[0]
			var active: Array = pair[1]
			var kept := []
			for index in world.dormant[collection].size():
				var entry: Dictionary = world.dormant[collection][index]
				# Indices in plan refer to the old dormant list; new parked records
				# are appended after it and cannot wake during the same transition.
				if index in changes["wake_"+collection]:
					var relative := Address.relative(entry.chunk,Vector2.ZERO,world.origin_chunk)
					if not relative.get("ok",false): return relative
					var restored := translate_record(entry.record,relative.local)
					if not restored.get("ok",false): return restored
					active.append(restored.record)
					if collection == "entities": woken_entities.append(restored.record.id)
				else: kept.append(entry)
			world.dormant[collection] = kept
		if not dormant_shape(world.dormant) or drops.size()+world.dormant.drops.size() > MAX_DROPS or entities.size()+world.dormant.entities.size() > 512: return failure("working_set_capacity")
	state.entities = entities
	state.drops = drops
	if world_changed: state.world = world
	return {"ok":true,"changed":true,"world_changed":world_changed,"retired":changes.retire.size(),"retired_entity_ids":retired_entity_ids,"parked_entities":changes.park_entities.size(),"parked_drops":changes.park_drops.size(),"woken_entities":woken_entities,"woken_drops":changes.wake_drops.size()}
static func translate_record(source: Dictionary, offset: Vector2) -> Dictionary:
	var record := source.duplicate(true)
	for field in POSITION_FIELDS:
		if not record.has(field): continue
		if not point_valid(record[field]): return failure("invalid_snapshot")
		var point := vec(record[field])+offset
		if not point_valid([point.x,point.y]): return failure("invalid_snapshot")
		record[field] = [point.x,point.y]
	if record.has("geometry"):
		if not record.geometry is Dictionary: return failure("invalid_snapshot")
		for field in ["position","origin","target","center"]:
			if not record.geometry.has(field): continue
			if not point_valid(record.geometry[field]): return failure("invalid_snapshot")
			var point := vec(record.geometry[field])+offset
			if not point_valid([point.x,point.y]): return failure("invalid_snapshot")
			record.geometry[field] = [point.x,point.y]
	return {"ok":true,"record":record}

static func drop_target(state: Dictionary, position: Array) -> Dictionary:
	if not point_valid(position) or not dormant_shape(state.world.get("dormant")): return failure("invalid_snapshot")
	var source := Address.normalize(state.world.origin_chunk,vec(position))
	if not source.get("ok",false): return source
	var local := [source.local.x,source.local.y]
	var cell := Vector2i(floor(source.local.x/16.0),floor(source.local.y/16.0))
	var best := {"ok":true,"kind":"append"}
	var best_distance := INF
	for kind in ["active","dormant"]:
		var records: Array = state.drops if kind == "active" else state.world.dormant.drops
		for index in records.size():
			var entry: Dictionary
			if kind == "active":
				var normalized := Address.normalize(state.world.origin_chunk,vec(records[index].position))
				if not normalized.get("ok",false): return normalized
				entry = {"chunk":normalized.chunk,"record":{"position":[normalized.local.x,normalized.local.y]}}
			else: entry = records[index]
			var point := vec(entry.record.position)
			if entry.chunk == source.chunk and Vector2i(floor(point.x/16.0),floor(point.y/16.0)) == cell: return {"ok":true,"kind":kind,"index":index}
			var distance := distance_squared(source.chunk,local,entry.chunk,entry.record.position)
			if not distance.get("ok",false): return distance
			if distance.value < best_distance:
				best_distance = distance.value
				best = {"ok":true,"kind":kind,"index":index}
	return best if state.drops.size()+state.world.dormant.drops.size() >= MAX_DROPS else {"ok":true,"kind":"append"}
