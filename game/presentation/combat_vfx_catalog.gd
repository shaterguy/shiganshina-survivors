class_name CombatVfxCatalog
extends RefCounted
const SKILLS := ["blade_slash|","spin_slash|","odm_dash|","reentry_combo|","wall_cannon|","ally_cover|","blade_slash|evo_wing_cut","wall_cannon|evo_crossfire","chain_lightning|","chain_lightning|evo_storm_chain","fire_zone|","fire_zone|evo_inferno_zone"]
const ROLES := ["cast","projectile","aim","impact","trail","area"]
const PASSES := ["ground","world","contact_overlay"]
var _data: Dictionary = {}
var _art_specs: Dictionary = {}
var _inferno_field_ratio := 0.0
func _init(definitions: Dictionary = {}) -> void:
	if not definitions.is_empty():
		_data = definitions.duplicate(true)
	else:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat_vfx.json"))
		if parsed is Dictionary: _data = parsed
	for requirement in _data.get("art_requirements",[]):
		_art_specs[str(requirement.get("art_id",""))] = requirement.duplicate(true)
	# A final pending eruption carries its larger radius. Recover the frozen
	# field radius using authored gameplay proportions, never today's passives.
	var evolutions = JSON.parse_string(FileAccess.get_file_as_string("res://data/evolutions.json"))
	if evolutions is Dictionary:
		var params: Dictionary = evolutions.get("items",{}).get("evo_inferno_zone",{}).get("effect_params",{})
		if float(params.get("eruption_radius",0.0)) > 0:
			_inferno_field_ratio = float(params.get("radius",0.0))/float(params.eruption_radius)
func fire_field_radius(record: Dictionary) -> float:
	var radius := float(record.get("radius",0.0))
	if record.get("evolution_id","") == "evo_inferno_zone" and int(record.get("stage_index",0)) == int(record.get("stage_count",0))-1:
		return radius*_inferno_field_ratio
	return radius
func definition_data() -> Dictionary:
	return _data.duplicate(true)
func art_requirements() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for requirement in _data.get("art_requirements",[]): output.append(requirement.duplicate(true))
	return output
func recipe(base_item_id: String, evolution_id: String, phase: String) -> Dictionary:
	for record in _data.get("recipes",[]):
		if record.get("base_item_id","") == base_item_id and record.get("evolution_id","") == evolution_id:
			var result: Dictionary = record.get("phases",{}).get(phase,{}).duplicate(true)
			if not result.is_empty():
				result.base_item_id = base_item_id
				result.evolution_id = evolution_id
				result.visual_identity = record.get("visual_identity","")
			return result
	return {}
func validate(manifest: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var seen: Array[String] = []
	var skills: Array[String] = []
	var phase_ids: Array[String] = []
	var assets: Dictionary = manifest.get("assets",{})
	for record in _data.get("recipes",[]):
		var id := str(record.get("recipe_id",""))
		if id.is_empty() or id in seen: errors.append("duplicate_recipe:"+id)
		seen.append(id)
		var skill := str(record.get("base_item_id",""))+"|"+str(record.get("evolution_id",""))
		if not skill in SKILLS or skill in skills: errors.append("invalid_skill:"+skill)
		skills.append(skill)
		var phases: Dictionary = record.get("phases",{})
		if not phases.has("cast"): errors.append("missing_cast:"+id)
		for phase in phases:
			var p: Dictionary = phases[phase]
			var pid := str(p.get("recipe_id",""))
			if pid.is_empty() or pid in phase_ids: errors.append("duplicate_phase:"+pid)
			phase_ids.append(pid)
			if not p.get("role","") in ROLES: errors.append("invalid_role:"+pid)
			if not p.get("render_pass","") in PASSES: errors.append("invalid_pass:"+pid)
			var duration = p.get("duration_ticks",-1)
			if not (duration is int or duration is float) or not is_finite(float(duration)) or duration < 0 or duration != floor(float(duration)): errors.append("invalid_duration:"+pid)
			for key in ["anchor_policy","contact_tick_policy","shape_binding"]:
				if str(p.get(key,"")).is_empty(): errors.append("missing_field:"+pid+":"+key)
			var layers: Array = p.get("layers",[])
			if layers.is_empty() or layers[0].get("reduce_mode","") != "preserve": errors.append("missing_main_shape:"+pid)
			for layer in layers:
				if not layer.get("render_pass","") in PASSES: errors.append("invalid_pass:"+pid)
				_validate_art(str(layer.get("art_id","")),assets,errors)
	for skill in SKILLS:
		if not skill in skills: errors.append("missing_skill:"+skill)
	# Damage feedback is deliberately independent of player cast identities.
	_validate_art("vfx_hit_spark",assets,errors)
	return errors
func _validate_art(id: String, assets: Dictionary, errors: Array[String]) -> void:
	if id.is_empty() or not assets.has(id):
		_append_error(errors,"missing_art:"+id)
		return
	var metadata = assets[id]
	for error in validate_art_metadata(id,metadata): _append_error(errors,error)
	var problem := render_problem(id,metadata)
	if not problem.is_empty() and problem != "invalid_art_metadata": _append_error(errors,problem+":"+id)
# Activation is separate from native review. Legacy reviewed originals retain
# their existing gate; new originals need every explicit development field.
static func render_enabled(metadata: Dictionary) -> bool:
	var approved = metadata.get("vfx_approved",null)
	if approved is bool and approved: return true
	return approved is bool and not approved and metadata.get("kind") == "effect" and metadata.get("source_status") == "NEW" and _strict_flag(metadata,"development_render_enabled",true) and _strict_flag(metadata,"native_reviewed",false) and _strict_flag(metadata,"final_art_approved",false) and metadata.get("review_status") == "development_enabled_native_review_pending"
static func _strict_flag(metadata: Dictionary, key: String, expected: bool) -> bool:
	return metadata.get(key,null) is bool and metadata[key] == expected
func render_problem(id: String, metadata: Variant, raster_validator: Callable = Callable()) -> String:
	if not validate_art_metadata(id,metadata).is_empty(): return "invalid_art_metadata"
	if not render_enabled(metadata): return "unapproved_art"
	# Direct command construction verifies actual bytes. Bridge supplies its one
	# existing config-scoped validator for its own immutable metadata, avoiding
	# per-frame I/O/decode. No caller-controlled context receipt bypasses policy.
	if metadata.get("vfx_approved") == false:
		return str(raster_validator.call(id)) if raster_validator.is_valid() else raster_problem(metadata)
	return ""
static func raster_problem(asset: Dictionary) -> String:
	var path := str(asset.get("path",""))
	if not FileAccess.file_exists(path): return "missing_raster"
	if FileAccess.get_sha256(path).to_lower() != str(asset.get("sha256","")).to_lower(): return "asset_hash_mismatch"
	var raster := Image.new()
	var loaded := raster.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	if loaded != OK or raster.is_empty() or raster.get_width() != int(asset.get("width",0)) or raster.get_height() != int(asset.get("height",0)): return "invalid_raster_dimensions"
	return ""
func validate_art_metadata(id: String, metadata: Variant) -> Array[String]:
	# Structural authority is the authored per-ID contract, never an approval flag.
	# This pure check can inspect an unapproved QA candidate without approving it.
	# render_problem adds the shared activation and original-byte policy.
	var errors: Array[String] = []
	if not _art_specs.has(id):
		_metadata_issue(errors,id,"unknown_requirement")
		return errors
	if not metadata is Dictionary:
		_metadata_issue(errors,id,"record")
		return errors
	var requirement: Dictionary = _art_specs[id]
	if metadata.get("kind","") != "effect": _metadata_issue(errors,id,"kind")
	var path = metadata.get("path",null)
	if not path is String or not str(path).ends_with(".png"): _metadata_issue(errors,id,"path")
	if not _digest_valid(metadata.get("sha256",null)): _metadata_issue(errors,id,"sha256")
	var expected_cell: Array = requirement.cell_px
	var expected_columns := int(requirement.columns)
	var expected_frames := int(requirement.frames)
	var expected_rows := int(ceil(float(expected_frames)/expected_columns))
	var expected_dimensions := {"cell_w":expected_cell[0],"cell_h":expected_cell[1],"width":int(expected_cell[0])*expected_columns,"height":int(expected_cell[1])*expected_rows,"columns":expected_columns}
	for key in expected_dimensions:
		var value = metadata.get(key,null)
		if not _whole_number(value,1) or value != expected_dimensions[key]: _metadata_issue(errors,id,key)
	var pivot = metadata.get("anchor_px",null)
	if not _finite_array(pivot,2):
		_metadata_issue(errors,id,"anchor_px")
	else:
		for index in 2:
			if not _whole_number(pivot[index],0) or pivot[index] != requirement.pivot_px[index]: _metadata_issue(errors,id,"anchor_px")
	var bounds = metadata.get("vfx_bounds_px",null)
	if not _finite_array(bounds,4):
		_metadata_issue(errors,id,"vfx_bounds_px")
	else:
		var valid_bounds: bool = bounds[0] >= 0 and bounds[1] >= 0 and bounds[2] > 0 and bounds[3] > 0 and bounds[0]+bounds[2] <= expected_cell[0] and bounds[1]+bounds[3] <= expected_cell[1]
		for index in 4:
			valid_bounds = valid_bounds and _whole_number(bounds[index],0) and bounds[index] == requirement.contact_bounds_px[index]
		if not valid_bounds: _metadata_issue(errors,id,"vfx_bounds_px")
	var animations = metadata.get("animations",null)
	if not animations is Dictionary or not animations.get("attack",null) is Dictionary:
		_metadata_issue(errors,id,"animations.attack")
	else:
		var attack: Dictionary = animations.attack
		var frames = attack.get("frames",null)
		if not frames is Array or frames.size() != expected_frames:
			_metadata_issue(errors,id,"frames")
		else:
			for index in frames.size():
				# Eight row-major frames are the authored layout. This also proves
				# every selected atlas region lies inside the declared image.
				if not _whole_number(frames[index],0) or frames[index] >= expected_rows*expected_columns or frames[index] != index: _metadata_issue(errors,id,"frames")
		var loop = attack.get("loop",false)
		if not loop is bool or loop: _metadata_issue(errors,id,"source_loop")
		if attack.has("fps") and (not _finite_number(attack.fps) or attack.fps <= 0): _metadata_issue(errors,id,"fps")
	if metadata.has("contact_frame") and (not _whole_number(metadata.contact_frame,0) or metadata.contact_frame != requirement.contact_frame): _metadata_issue(errors,id,"contact_frame")
	if metadata.has("forward_axis") and metadata.forward_axis != requirement.forward_axis: _metadata_issue(errors,id,"forward_axis")
	return errors
func _metadata_issue(errors: Array[String], id: String, field: String) -> void:
	_append_error(errors,"invalid_art_metadata:"+id+":"+field)
func _append_error(errors: Array[String], error: String) -> void:
	if not error in errors: errors.append(error)
func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
func _whole_number(value: Variant, minimum: int) -> bool:
	return _finite_number(value) and value >= minimum and value == floor(float(value))
func _finite_array(value: Variant, size: int) -> bool:
	if not value is Array or value.size() != size: return false
	for item in value:
		if not _finite_number(item): return false
	return true
func _digest_valid(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for index in value.length():
		if not value.substr(index,1).to_lower() in "0123456789abcdef": return false
	return true
