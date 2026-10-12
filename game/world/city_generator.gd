class_name CityGenerator
extends RefCounted
const Address = preload("res://game/world/world_address.gd")
const Catalog = preload("res://game/world/world_prop_catalog.gd")
var _templates: Dictionary
var _props: Dictionary
var _catalog
func _init(templates: Dictionary, props: Dictionary) -> void:
	_templates = templates.duplicate(true)
	_props = props.duplicate(true)
	_catalog = Catalog.new(_props)
func validate() -> Array[String]:
	var errors: Array[String] = []
	if _templates.get("generator_revision") != "city_v1" or _templates.get("template_revision") != "ch01_city_1" or _templates.get("chunk_size") != 768 or _templates.get("navigation_cell") != 32 or _templates.get("street_interval") != [288.0,480.0] or _templates.get("passage_rect") != [336.0,336.0,96.0,96.0]: errors.append("invalid_template_contract")
	var templates: Array = _templates.get("templates",[])
	if templates.size() != 4: errors.append("four_templates_required")
	var ids := {}
	for template in templates:
		if ids.has(template.template_id): errors.append("duplicate_template")
		ids[template.template_id] = true
		var slots := {}
		var solids: Array[Rect2] = []
		if template.slots.size() > 12: errors.append("too_many_props")
		for slot in template.slots:
			if slots.has(slot.slot_id) or slot.slot_id.is_empty(): errors.append("duplicate_slot")
			slots[slot.slot_id] = true
			if slot.get("rotation_degrees",0) != 0: errors.append("unsupported_rotation")
			var prop: Dictionary = _catalog.place("city:city_v1:0:0:"+slot.slot_id,slot.definition_id,Vector2(slot.position[0],slot.position[1]),{})
			if prop.is_empty():
				errors.append("unknown_slot_definition")
				continue
			if prop.collision_mask != 0:
				var r: Rect2 = prop.ground_footprint
				if not Rect2(0,0,768,768).encloses(r) or r.intersects(Rect2(288,0,192,768)) or r.intersects(Rect2(0,288,768,192)): errors.append("solid_in_reserved_street")
				solids.append(r)
		for radius in [8.0,32.0]:
			if not _connected(solids,radius): errors.append("unreachable_or_long_retreat:"+template.template_id)
	return errors
func generate(seed: int, chunk: Array) -> Dictionary:
	var digest: String = Address.domain_digest(seed,chunk,"layout")
	if digest.is_empty() or _templates.get("templates",[]).is_empty(): return {}
	var template: Dictionary = _templates.templates[digest.substr(0,8).hex_to_int()%_templates.templates.size()]
	var placed: Array = []
	for slot in template.slots:
		var id: String = "city:city_v1:%s:%s:%s" % [chunk[0],chunk[1],slot.slot_id]
		placed.append(_catalog.place(id,slot.definition_id,Vector2(slot.position[0],slot.position[1]),{}))
	placed.sort_custom(func(a,b): return a.prop_id < b.prop_id)
	return {"chunk_id":Address.key(chunk),"chunk":chunk.duplicate(),"ground_variant":Address.domain_digest(seed,chunk,"ground").substr(0,8).hex_to_int()%4,"decor_variant":Address.domain_digest(seed,chunk,"decor").substr(0,8).hex_to_int()%4,"props":placed,"ports":{"north":[288,480],"south":[288,480],"west":[288,480],"east":[288,480]},"street_nodes":[Vector2(384,0),Vector2(768,384),Vector2(384,768),Vector2(0,384),Vector2(384,384)],"passage_rect":Rect2(336,336,96,96),"template_id":template.template_id,"geometry_revision":0}
func hydrate(chunk: Dictionary, deltas: Array) -> Dictionary:
	var result: Dictionary = chunk.duplicate(true)
	var seen := {}
	for delta in deltas:
		if not delta is Dictionary or not delta.has("slot_id") or not delta.has("hp") or not delta.has("destroyed") or seen.has(delta.slot_id): return {"ok":false,"error_code":"invalid_prop_delta"}
		seen[delta.slot_id] = true
		var found := false
		for i in result.props.size():
			var prop: Dictionary = result.props[i]
			if prop.slot_id != delta.slot_id: continue
			var placed: Dictionary = _catalog.place(prop.prop_id,prop.definition_id,prop.position,delta)
			if placed.is_empty(): return {"ok":false,"error_code":"invalid_prop_delta"}
			result.props[i] = placed
			found = true
		if not found: return {"ok":false,"error_code":"unknown_prop_slot"}
	return {"ok":true,"chunk":result}
static func _connected(solids: Array[Rect2], radius: float) -> bool:
	var flags := PackedByteArray()
	var distances := PackedInt32Array()
	flags.resize(576)
	distances.resize(576)
	distances.fill(-1)
	var queue: Array[int] = []
	for y in 24:
		for x in 24:
			var point := Vector2(x*32+16,y*32+16)
			var blocked := false
			for r in solids:
				var box := r.grow(radius)
				if point.x > box.position.x and point.x < box.end.x and point.y > box.position.y and point.y < box.end.y: blocked = true
			flags[y*24+x] = 0 if blocked else 1
			if not blocked and Rect2(336,336,96,96).has_point(point):
				distances[y*24+x] = 0
				queue.append(y*24+x)
	var head := 0
	while head < queue.size():
		var id := queue[head]
		head += 1
		for offset in [Vector2i(0,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(0,1)]:
			var x: int = id%24+offset.x
			var y: int = id/24+offset.y
			if x < 0 or y < 0 or x >= 24 or y >= 24: continue
			var next := y*24+x
			if flags[next] == 1 and distances[next] < 0:
				distances[next] = distances[id]+32
				queue.append(next)
	for i in 576:
		if flags[i] == 1 and (distances[i] < 0 or distances[i] > 900): return false
	return true
