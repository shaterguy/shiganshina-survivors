class_name StreamedWorld
extends RefCounted
const Address = preload("res://game/world/world_address.gd")
const Codec = preload("res://game/world/world_delta_codec.gd")
const MAX_NORMAL := 49
const MAX_POOL := 64
const BUCKET := 128
var _generator
var _seed: int
var _origin: Array = ["0","0"]
var _chunks: Dictionary = {}
var _dirty: Dictionary = {}
var _props: Dictionary = {}
var _buckets: Dictionary = {}
var _collision_bucket_cache: Dictionary = {}
var _world_revision := 0
var _coverage_revision := 0
var _last_error := ""
var _peak := 0
var _query_count := 0
var _peak_pool := 0
var _clearance_cache: Dictionary = {}
func _init(generator, seed: int = 0) -> void:
	_generator = generator
	_seed = seed
func prepare(required: Array, prefetch: Array, hydrated_deltas: Dictionary, origin: Array, admission_center: Array = []) -> Dictionary:
	# NEW continuity boundary: admission follows the player; saved origin still
	# owns every localized collision/render coordinate. Existing callers retain
	# the exact original centered behavior through the optional argument.
	if not Address.parse(origin).ok: return _failure("invalid_chunk_address")
	var center: Array = origin if admission_center.is_empty() else admission_center
	if not Address.parse(center).ok: return _failure("invalid_chunk_address")
	var requested := {}
	for value in required+prefetch:
		if not value is Array or not Address.parse(value).ok: return _failure("invalid_chunk_address")
		var local: Dictionary = Address.relative(value,Vector2.ZERO,center)
		if not local.ok or absf(local.local.x) > 2304 or absf(local.local.y) > 2304: return _failure("outside_working_set")
		# Validate localization before publishing any privately generated chunks.
		if not Address.relative(value,Vector2.ZERO,origin).ok: return _failure("outside_working_set")
		requested[Address.key(value)] = value.duplicate()
	if requested.size() > MAX_NORMAL: return _failure("working_set_capacity")
	var missing: Array = []
	var ordered: Array = requested.values()
	ordered.sort_custom(Address.less)
	for chunk in ordered:
		var key: String = Address.key(chunk)
		if not hydrated_deltas.has(key): missing.append(key)
		elif not hydrated_deltas[key] is Array: return _failure("invalid_hydration")
	if not missing.is_empty(): return {"ok":false,"error_code":"world_not_ready","missing_delta_keys":missing,"activated":[],"retired":[]}
	var retained := requested.size()
	for key in _dirty:
		if not requested.has(key): retained += 1
	if retained > MAX_POOL: return _failure("delta_stage_required")
	var pool_size := _chunks.size()
	for key in requested:
		if not _chunks.has(key): pool_size += 1
	if pool_size > MAX_POOL: return _failure("handover_capacity")
	var next: Dictionary = {}
	var activated: Array = []
	var retired: Array = []
	for chunk in ordered:
		var key: String = Address.key(chunk)
		if _chunks.has(key):
			# Validate the packet even when geometry is resident. A verified older
			# disk state must never replace newer live/dirty prop state here.
			var validated: Dictionary = _generator.hydrate(_chunks[key],hydrated_deltas[key])
			if not validated.ok: return _failure(validated.error_code)
			next[key] = _chunks[key]
		else:
			var generated: Dictionary = _generator.generate(_seed,chunk)
			if generated.is_empty(): return _failure("invalid_generator")
			var hydrated: Dictionary = _generator.hydrate(generated,hydrated_deltas[key])
			if not hydrated.ok: return _failure(hydrated.error_code)
			next[key] = hydrated.chunk
			activated.append(key)
	var old: Array = _chunks.values()
	old.sort_custom(func(a,b): return Address.less(a.chunk,b.chunk))
	for chunk in old:
		if next.has(chunk.chunk_id): continue
		if _dirty.has(chunk.chunk_id):
			if not Address.relative(chunk.chunk,Vector2.ZERO,origin).ok: return _failure("delta_stage_required")
			next[chunk.chunk_id] = chunk
		else: retired.append(chunk.chunk_id)
	if _origin != origin or not activated.is_empty() or not retired.is_empty(): _coverage_revision += 1
	_peak_pool = maxi(_peak_pool,pool_size)
	_origin = origin.duplicate()
	_chunks = next
	_peak = maxi(_peak,_chunks.size())
	_rebuild()
	_last_error = ""
	return {"ok":true,"missing_delta_keys":[],"activated":activated,"retired":retired}
func apply_props(changes: Array, world_revision: int) -> Dictionary:
	if world_revision <= _world_revision: return _failure("stale_world_revision")
	var candidates := {}
	for change in changes:
		if not change is Dictionary or not change.get("chunk") is Array or not change.get("props") is Array: return _failure("invalid_prop_delta")
		var key: String = Address.key(change.chunk)
		if not _chunks.has(key) or candidates.has(key): return _failure("invalid_prop_delta")
		var hydrated: Dictionary = _generator.hydrate(_chunks[key],change.props)
		if not hydrated.ok: return _failure(hydrated.error_code)
		hydrated.chunk.geometry_revision = int(_chunks[key].geometry_revision)+1
		candidates[key] = hydrated.chunk
	for key in candidates:
		_chunks[key] = candidates[key]
		_dirty[key] = world_revision
	_world_revision = world_revision
	_rebuild()
	return {"ok":true,"changed_chunk_ids":candidates.keys(),"world_revision":world_revision}
func acknowledge_staged(chunk_ids: Array, world_revision: int) -> Dictionary:
	# Only C, after exact root/revision/digest receipt validation, may call this.
	if world_revision != _world_revision: return _failure("stale_world_revision")
	for key in chunk_ids:
		if not _dirty.has(key): return _failure("unknown_dirty_chunk")
	for key in chunk_ids: _dirty.erase(key)
	return {"ok":true}
func _prepare_persisted_subset(current_records: Array, captured_records: Array, world_revision: int) -> Dictionary:
	# Pure preflight. Unlike _failure(), refusals must not mutate diagnostics.
	if _world_revision != world_revision: return Codec.fail("world_ack_stale")
	var current := Codec.normalize_records(current_records)
	var captured := Codec.normalize_records(captured_records)
	if not current.ok or not captured.ok: return Codec.fail("world_ack_invalid")
	if not _ack_same_records(current.records,current_records) or not _ack_same_records(captured.records,captured_records): return Codec.fail("world_ack_invalid")
	if _dirty.size() != current_records.size(): return Codec.fail("world_ack_bookkeeping")
	var by_key := {}
	for record in current_records:
		var key := Address.key(record.chunk)
		if not _dirty.has(key) or not Codec.integer(_dirty[key]) or _dirty[key] < 1 or _dirty[key] > world_revision or not _chunks.has(key): return Codec.fail("world_ack_bookkeeping")
		var chunk: Dictionary = _chunks[key]
		if chunk.get("chunk") != record.chunk or chunk.get("chunk_id") != key or not chunk.get("props") is Array: return Codec.fail("world_ack_bookkeeping")
		var projected := []
		for prop in chunk.props:
			if not prop is Dictionary or not prop.get("prop_id") is String or not _props.get(prop.prop_id) is Dictionary: return Codec.fail("world_ack_geometry")
			var local: Dictionary = _props[prop.prop_id]
			for field in ["slot_id","destructible","hp","max_hp","destroyed"]:
				if not prop.has(field) or not local.has(field) or typeof(prop[field]) != typeof(local[field]) or prop[field] != local[field]: return Codec.fail("world_ack_geometry")
			if not prop.destructible is bool or not prop.destroyed is bool or not Codec.integer(prop.hp) or not Codec.integer(prop.max_hp) or prop.hp > prop.max_hp: return Codec.fail("world_ack_geometry")
			if prop.destructible:
				if prop.destroyed != (prop.hp == 0): return Codec.fail("world_ack_geometry")
				if prop.destroyed or prop.hp != prop.max_hp: projected.append({"slot_id":prop.slot_id,"hp":prop.hp,"destroyed":prop.destroyed})
		var projection := Codec.normalize_records([{"chunk":record.chunk,"props":projected}])
		if not projection.ok or not _ack_same_records(projection.records,[record]): return Codec.fail("world_ack_incomplete")
		by_key[key] = record
	var next_dirty := _dirty.duplicate(true)
	for record in captured_records:
		var key := Address.key(record.chunk)
		if not by_key.has(key) or not _chunks.has(key): return Codec.fail("world_ack_missing_chunk")
		var slots := {}
		for prop in by_key[key].props: slots[prop.slot_id] = prop
		for prop in record.props:
			# Destruction is monotone. Omitted old slots or healing cannot prove
			# a complete whole-record replacement over the captured base.
			if not slots.has(prop.slot_id) or slots[prop.slot_id].hp > prop.hp or (prop.destroyed and not slots[prop.slot_id].destroyed): return Codec.fail("world_ack_incomplete")
		if _ack_same_records([record],[by_key[key]]): next_dirty.erase(key)
	return {"ok":true,"next_dirty":next_dirty}
func _apply_persisted_subset(next_dirty: Dictionary) -> void:
	# Private paired apply; caller owns freshly prepared data and cannot yield.
	_dirty = next_dirty
static func _ack_same_records(left: Array, right: Array) -> bool:
	# Both arrays have already passed normalization. Numeric JSON int/float
	# equality is intended; shape, ordering and every slot remain exact.
	if left.size() != right.size(): return false
	for index in left.size():
		var a: Dictionary = left[index]
		var b: Dictionary = right[index]
		if a.chunk != b.chunk or a.props.size() != b.props.size(): return false
		for slot in a.props.size():
			if a.props[slot].slot_id != b.props[slot].slot_id or a.props[slot].hp != b.props[slot].hp or a.props[slot].destroyed != b.props[slot].destroyed: return false
	return true
func walkable(position: Vector2, radius: float) -> bool:
	if not _valid_query(position,Vector2.ZERO,radius): return false
	if not covered(Rect2(position-Vector2.ONE*radius,Vector2.ONE*radius*2)): return false
	for prop in _collision_query_props(Rect2(position-Vector2.ONE*radius,Vector2.ONE*radius*2)):
		if prop.collision_mask != 0 and _inside(position,_collision_box(prop,radius)): return false
	return true
func move(position: Vector2, delta: Vector2, radius: float) -> Vector2:
	if not _valid_query(position,delta,radius) or not covered(_swept_rect(position,delta,radius)): return position
	var point := position
	for axis in 2:
		if delta[axis] == 0.0: continue
		var step := Vector2.ZERO
		step[axis] = delta[axis]
		point = sweep(point,step,radius).position
	return point
func sweep(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
	return _sweep(position,delta,radius,3,false)
func cover_sweep(position: Vector2, delta: Vector2, radius: float, mask: int) -> Dictionary:
	return _sweep(position,delta,radius,mask,true)
func _sweep(position: Vector2, delta: Vector2, radius: float, mask: int, cover: bool) -> Dictionary:
	if not _valid_query(position,delta,radius): return {"ok":false,"error_code":"invalid_query","position":position,"hit_prop_id":"","fraction":0.0}
	if not covered(_swept_rect(position,delta,radius)): return {"ok":false,"error_code":"world_not_ready","position":position,"hit_prop_id":"","fraction":0.0}
	var fraction := 1.0
	var hit_id := ""
	for prop in _collision_query_props(_swept_rect(position,delta,radius)):
		var bits: int = prop.cover_mask if cover else prop.collision_mask
		if (bits & mask) == 0: continue
		var f := slab_fraction(position,delta,_collision_box(prop,radius))
		if f < fraction or (f == fraction and f < 1 and (hit_id.is_empty() or prop.prop_id < hit_id)):
			fraction = f
			hit_id = prop.prop_id
	var result := position+delta*fraction
	if not cover and not walkable(result,radius):
		result = position+delta*maxf(0,fraction-0.0002/maxf(delta.length(),1))
		if not walkable(result,radius): result = position
	return {"ok":true,"error_code":"","position":result,"hit_prop_id":hit_id,"fraction":fraction}
func query_props(aabb: Rect2) -> Array:
	return _query_props(aabb,true)
func _collision_query_props(aabb: Rect2) -> Array:
	# Only this exact implementation consumes borrowed records synchronously.
	# Derived query/collision callbacks retain the public, caller-owned path.
	if get_script() != StreamedWorld: return query_props(aabb)
	return _query_props(aabb,false)
func _query_props(aabb: Rect2, owned: bool) -> Array:
	_query_count += 1
	if not owned:
		var result: Array = []
		for prop in _collision_bucket_candidates(aabb):
			if prop.ground_footprint.intersects(aabb,true): result.append(prop)
		return result
	var selected := {}
	for y in range(int(floor(aabb.position.y/BUCKET)),int(floor(aabb.end.y/BUCKET))+1):
		for x in range(int(floor(aabb.position.x/BUCKET)),int(floor(aabb.end.x/BUCKET))+1):
			for id in _buckets.get(Vector2i(x,y),[]):
				if _props[id].ground_footprint.intersects(aabb,true): selected[id] = true
	var ids: Array = selected.keys()
	ids.sort()
	var result: Array = []
	for id in ids: result.append(_props[id].duplicate(true) if owned else _props[id])
	return result
func _collision_bucket_candidates(aabb: Rect2) -> Array:
	# Only exact synchronous collision readers reach this borrowed path. Cache
	# the sorted bucket superset, never an AABB result or a collision decision.
	var span := Vector4i(int(floor(aabb.position.x/BUCKET)),int(floor(aabb.position.y/BUCKET)),int(floor(aabb.end.x/BUCKET)),int(floor(aabb.end.y/BUCKET)))
	if _collision_bucket_cache.has(span): return _collision_bucket_cache[span]
	var selected := {}
	for y in range(span.y,span.w+1):
		for x in range(span.x,span.z+1):
			for id in _buckets.get(Vector2i(x,y),[]): selected[id] = true
	var ids: Array = selected.keys()
	ids.sort()
	var result: Array = []
	for id in ids: result.append(_props[id])
	# Uncommon/large spans still run the exact query without retaining records.
	if _collision_bucket_cache.size() < 512 and (span.z-span.x+1)*(span.w-span.y+1) <= 256:
		_collision_bucket_cache[span] = result
	return result
func covered(aabb: Rect2) -> bool:
	var low_x := int(floor(aabb.position.x/768))
	var high_x := int(floor((aabb.end.x-0.0001 if aabb.size.x > 0 else aabb.end.x)/768))
	var low_y := int(floor(aabb.position.y/768))
	var high_y := int(floor((aabb.end.y-0.0001 if aabb.size.y > 0 else aabb.end.y)/768))
	if high_x-low_x > 8 or high_y-low_y > 8: _last_error = "world_not_ready"; return false
	for y in range(low_y,high_y+1):
		for x in range(low_x,high_x+1):
			var point := Address.normalize(_origin,Vector2(x*768,y*768))
			if not point.ok or not _chunks.has(Address.key(point.chunk)):
				_last_error = "world_not_ready"
				return false
	return true
func chunk_at(position: Vector2) -> Dictionary:
	var n := Address.normalize(_origin,position)
	if not n.ok: return {}
	var key: String = Address.key(n.chunk)
	return localized_chunk(key)
func localized_chunk(key: String) -> Dictionary:
	if not _chunks.has(key): return {}
	var chunk: Dictionary = _chunks[key].duplicate(true)
	var translation: Vector2 = Address.relative(chunk.chunk,Vector2.ZERO,_origin).local
	chunk.local_origin = translation
	for i in chunk.props.size(): chunk.props[i] = _props[chunk.props[i].prop_id].duplicate(true)
	chunk.passage_rect.position += translation
	for i in chunk.street_nodes.size(): chunk.street_nodes[i] += translation
	return chunk
func render_view() -> Dictionary:
	var chunks: Array = []
	for key in _chunks: chunks.append(localized_chunk(key))
	chunks.sort_custom(func(a,b): return Address.less(a.chunk,b.chunk))
	return {"stage":"city","origin_chunk":_origin.duplicate(),"origin_revision":_coverage_revision,"chunks":chunks}
func chunk_keys() -> Array:
	return _chunks.keys()
func diagnostics() -> Dictionary:
	return {"resident_chunks":_chunks.size(),"resident_props":_props.size(),"dirty_chunks":_dirty.size(),"peak_resident_chunks":_peak,"peak_pool_chunks":_peak_pool,"clearance_cache_entries":_clearance_cache.size(),"spatial_buckets":_buckets.size(),"world_revision":_world_revision,"coverage_revision":_coverage_revision,"query_count":_query_count,"last_error":_last_error}
func _rebuild() -> void:
	_collision_bucket_cache.clear()
	for key in _clearance_cache.keys():
		var cached: Dictionary = _clearance_cache[key]
		var chunk: Dictionary = _chunks.get(cached.chunk_id,{})
		if chunk.is_empty() or chunk.geometry_revision != cached.revision or _origin != cached.origin: _clearance_cache.erase(key)
	_props.clear()
	_buckets.clear()
	for chunk in _chunks.values():
		var offset: Vector2 = Address.relative(chunk.chunk,Vector2.ZERO,_origin).local
		for original in chunk.props:
			var prop: Dictionary = original.duplicate(true)
			prop.position += offset
			prop.ground_footprint.position += offset
			prop.render_bounds.position += offset
			prop.depth_y += offset.y
			prop.chunk_id = chunk.chunk_id
			prop.geometry_revision = chunk.geometry_revision
			_props[prop.prop_id] = prop
			if prop.collision_mask == 0 and prop.cover_mask == 0: continue
			var r: Rect2 = prop.ground_footprint
			for y in range(int(floor(r.position.y/BUCKET)),int(floor(r.end.y/BUCKET))+1):
				for x in range(int(floor(r.position.x/BUCKET)),int(floor(r.end.x/BUCKET))+1):
					var key := Vector2i(x,y)
					if not _buckets.has(key): _buckets[key] = []
					_buckets[key].append(prop.prop_id)
func _collision_box(prop: Dictionary, radius: float) -> Rect2:
	# Exact worlds grow directly; derived callbacks retain legacy memoization.
	if get_script() == StreamedWorld: return prop.ground_footprint.grow(radius)
	# Exact collision radii are never rounded. Only finite declared classes cache;
	# arbitrary intermediate radii expand on demand without growing the cache.
	if not radius in [8.0,16.0,18.0,20.0,24.0,28.0,30.0,32.0]: return prop.ground_footprint.grow(radius)
	var key: String = "%s:%d" % [prop.chunk_id,int(radius)]
	if not _clearance_cache.has(key): _clearance_cache[key] = {"chunk_id":prop.chunk_id,"revision":prop.geometry_revision,"origin":_origin.duplicate(),"boxes":{}}
	var boxes: Dictionary = _clearance_cache[key].boxes
	if not boxes.has(prop.prop_id): boxes[prop.prop_id] = prop.ground_footprint.grow(radius)
	return boxes[prop.prop_id]
static func slab_fraction(position: Vector2, delta: Vector2, box: Rect2) -> float:
	var enter := -INF
	var leave := INF
	for axis in 2:
		if delta[axis] == 0:
			if position[axis] <= box.position[axis] or position[axis] >= box.end[axis]: return 1.0
		else:
			var first: float = (box.position[axis]-position[axis])/delta[axis]
			var last: float = (box.end[axis]-position[axis])/delta[axis]
			enter = maxf(enter,minf(first,last))
			leave = minf(leave,maxf(first,last))
	return clampf(enter,0,1) if leave > maxf(0,enter) and enter < 1 else 1.0
static func _swept_rect(position: Vector2, delta: Vector2, radius: float) -> Rect2:
	return Rect2(position.min(position+delta)-Vector2.ONE*radius,delta.abs()+Vector2.ONE*radius*2)
static func _inside(point: Vector2, box: Rect2) -> bool:
	return point.x > box.position.x and point.x < box.end.x and point.y > box.position.y and point.y < box.end.y
static func _valid_query(p: Vector2, d: Vector2, r: float) -> bool:
	return is_finite(p.x) and is_finite(p.y) and is_finite(d.x) and is_finite(d.y) and is_finite(r) and r >= 0 and r <= 32 and p.abs().x <= 49152 and p.abs().y <= 49152 and d.length() <= 49152
func _failure(code: String) -> Dictionary:
	_last_error = code
	return {"ok":false,"error_code":code,"missing_delta_keys":[],"activated":[],"retired":[]}
