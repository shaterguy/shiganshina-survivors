class_name WorldPropCatalog
extends RefCounted
const PLAYER := 1
const GROUNDED_TITAN := 2
const PHYSICAL_ATTACK := 4
const STRAIGHT_PROJECTILE := 8
const OVERHEAD := 16
var _definitions: Dictionary
func _init(definitions: Dictionary = {}) -> void:
	_definitions = definitions.get("definitions",{}).duplicate(true)
static func validate(definitions: Dictionary, asset_manifest: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var masks: Dictionary = definitions.get("mask_bits",{})
	for pair in [["player",1],["grounded_titan",2],["physical_attack",4],["straight_projectile",8],["overhead",16]]:
		if masks.get(pair[0],-1) != pair[1]: errors.append("invalid_mask_assignment:"+pair[0])
	var assets: Dictionary = asset_manifest.get("assets",{})
	var catalog: Dictionary = definitions.get("definitions",{})
	if catalog.is_empty(): errors.append("empty_catalog")
	for id in catalog:
		var d: Dictionary = catalog[id]
		if not assets.has(d.get("asset_id","")) or not assets.has(d.get("ruin_asset_id","")):
			errors.append("unknown_asset:"+id)
			continue
		var art: Dictionary = assets[d.asset_id]
		if d.get("anchor_px") != art.get("anchor_px") or d.get("render_bounds") != [-art.anchor_px[0],-art.anchor_px[1],art.cell_w,art.cell_h]: errors.append("asset_metadata:"+id)
		if d.get("rotation_degrees",0) != 0: errors.append("unsupported_rotation:"+id)
		for field in ["ground_footprint","render_bounds","ruin_footprint","ruin_render_bounds"]:
			if not _valid_rect(d.get(field)): errors.append("invalid_rect:"+id+":"+field)
		var hp = d.get("structure_hp",-1)
		if not (hp is int or hp is float) or not is_finite(float(hp)) or hp != floor(float(hp)) or hp < 0 or (d.get("destructible",false) and hp < 1): errors.append("invalid_hp:"+id)
		for mask in ["collision_mask","cover_mask"]:
			if not d.has(mask) or int(d[mask]) != d[mask] or d[mask] < 0 or d[mask] > 31: errors.append("invalid_mask:"+id)
		if d.get("contact_damage",0) != 0: errors.append("undeclared_contact_damage:"+id)
	return errors
func place(prop_id: String, definition_id: String, position: Vector2, delta: Dictionary) -> Dictionary:
	if not _definitions.has(definition_id) or prop_id.is_empty() or not is_finite(position.x) or not is_finite(position.y): return {}
	var d: Dictionary = _definitions[definition_id]
	var hp = delta.get("hp",d.structure_hp)
	var destroyed = delta.get("destroyed",false)
	if not (hp is int or hp is float) or not is_finite(float(hp)) or hp != floor(float(hp)) or hp < 0 or hp > d.structure_hp or not destroyed is bool: return {}
	if (d.destructible and destroyed != (hp == 0)) or (not d.destructible and (destroyed or not delta.is_empty())): return {}
	var footprint := rect(d.ruin_footprint if destroyed else d.ground_footprint)
	var art := rect(d.ruin_render_bounds if destroyed else d.render_bounds)
	footprint.position += position
	art.position += position
	return {"prop_id":prop_id,"definition_id":definition_id,"slot_id":prop_id.get_slice(":",4),"asset_id":d.ruin_asset_id if destroyed else d.asset_id,"position":position,"ground_footprint":footprint,"depth_y":position.y+float(d.depth_origin),"render_bounds":art,"collision_mask":0 if destroyed else int(d.collision_mask),"cover_mask":0 if destroyed else int(d.cover_mask),"destructible":d.destructible,"hp":int(hp),"max_hp":int(d.structure_hp),"destroyed":destroyed,"contact_damage":0,"pose":"ruined" if destroyed else ("damaged" if hp < d.structure_hp else "intact"),"rotation_degrees":0}
static func rect(v: Array) -> Rect2:
	return Rect2(float(v[0]),float(v[1]),float(v[2]),float(v[3]))
static func _valid_rect(v: Variant) -> bool:
	if not v is Array or v.size() != 4: return false
	for n in v:
		if not (n is int or n is float) or not is_finite(float(n)): return false
	return v[2] >= 0 and v[3] >= 0
