class_name CombatVfxRenderer
extends RefCounted
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
var _catalog = Catalog.new()
var _raster_validator: Callable
func _init(raster_validator: Callable = Callable()) -> void:
	_raster_validator = raster_validator
# Raster-only command builder. Consumers draw each pass; diagnostic records are
# deliberately not CanvasItem commands and never authorize placeholder geometry.
func commands(effects: Array[Dictionary], context: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var tick := int(context.get("tick",0))
	var metadata: Dictionary = context.get("asset_metadata",{})
	if metadata.has("assets"): metadata = metadata.assets
	# Validate each unique original once per command batch, including its bytes.
	var validation: Dictionary = {}
	for effect in effects:
		if tick < int(effect.get("start_tick",0)) or tick >= int(effect.get("end_tick",0)): continue
		if int(effect.get("origin_revision",0)) != int(context.get("origin_revision",0)):
			output.append(_diagnostic(effect,"stale_origin_revision",""))
			continue
		var layers: Array = effect.get("layers",[])
		for index in layers.size():
			var layer: Dictionary = layers[index]
			var component := str(layer.get("component","main"))
			# JSON numbers are floats; Array membership does not coerce an int.
			if layer.has("stage_indices") and not layer.stage_indices.any(func(stage): return float(stage) == float(effect.get("stage_index",0))): continue
			if effect.get("evolution_id","") == "evo_wing_cut":
				if int(effect.get("stage_index",0)) == 0 and component == "stage_second": continue
				if int(effect.get("stage_index",0)) == 1 and component == "main": continue
				if component == "stage_second": component = "main"
			if (context.get("reduce_effects",false) or effect.get("omit_optional",false)) and layer.get("reduce_mode","preserve") == "omit": continue
			var geometry: Dictionary = effect.get("geometry",{})
			if component == "wire" and not geometry.has("wire_anchor"): continue
			var asset_id := str(layer.get("art_id",""))
			if asset_id.is_empty() or not metadata.has(asset_id):
				output.append(_diagnostic(effect,"missing_art",asset_id))
				continue
			var asset = metadata[asset_id]
			if not validation.has(asset_id): validation[asset_id] = _catalog.render_problem(asset_id,asset,_raster_validator)
			var problem: String = validation[asset_id]
			if not problem.is_empty():
				var invalid := _diagnostic(effect,problem,asset_id)
				if problem == "invalid_art_metadata": invalid.metadata_errors = _catalog.validate_art_metadata(asset_id,asset)
				output.append(invalid)
				continue
			var command := _command(effect,layer,component,asset,tick,context,index)
			if command.has("diagnostic"):
				output.append(command)
			elif not context.has("visible_rect") or context.visible_rect.intersects(command.world_bounds):
				output.append(command)
	output.sort_custom(func(a,b):
		var pa := _pass_index(str(a.get("render_pass","world")))
		var pb := _pass_index(str(b.get("render_pass","world")))
		if pa != pb: return pa < pb
		if not is_equal_approx(float(a.get("depth_y",0)),float(b.get("depth_y",0))): return float(a.get("depth_y",0)) < float(b.get("depth_y",0))
		return str(a.get("stable_id","")) < str(b.get("stable_id","")))
	return output
func _command(effect: Dictionary, layer: Dictionary, component: String, asset: Dictionary, tick: int, context: Dictionary, index: int) -> Dictionary:
	var geometry: Dictionary = effect.get("geometry",{})
	var shape := str(geometry.get("shape",effect.get("shape_binding","point")))
	var anchor := _vec(effect.get("origin",geometry.get("origin",[0,0])))
	var direction := _vec(effect.get("direction",geometry.get("direction",[1,0])))
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	if shape == "targeted": anchor = _vec(geometry.get("position",geometry.get("origin",anchor)))
	if effect.get("projectile_binding","") == "core" and context.get("projectile_positions",{}).has(effect.get("projectile_id")):
		anchor = _vec(context.projectile_positions[effect.projectile_id])
	if effect.get("coordinate_space","world") == "actor":
		var actors: Dictionary = context.get("actor_positions",{})
		var id := str(effect.get("actor_id","player"))
		if not actors.has(id): return _diagnostic(effect,"missing_actor",str(layer.art_id))
		anchor = _vec(actors[id])+_vec(effect.get("actor_offset",Vector2.ZERO))
	var rotation := 0.0 if shape in ["circle","targeted","point"] else direction.angle()
	var radius := maxf(0.0,float(geometry.get("radius",0.0)))
	var contact_size := Vector2.ONE*maxf(radius*2.0,8.0)
	if shape == "line": contact_size = Vector2(maxf(0.001,float(geometry.get("length",radius))),maxf(0.001,float(geometry.get("width",1.0))))
	# A confirmed single-target hit owns a separate display footprint. The
	# unchanged contact_geometry below still records Core's acquisition geometry.
	if effect.has("contact_position"):
		if not Catalog.presentation_size_valid(effect.get("presentation_size_px",null)): return _diagnostic(effect,"invalid_presentation_size",str(layer.art_id))
		anchor = _vec(effect.contact_position)
		rotation = 0.0
		contact_size = _vec(effect.presentation_size_px)
	if component == "wire":
		var endpoint := _vec(geometry.wire_anchor)
		if not effect.has("contact_position") and effect.get("base_item_id","") != "chain_lightning" and context.get("target_positions",{}).has(geometry.get("target_id")):
			endpoint = _vec(context.target_positions[geometry.target_id])
		contact_size = Vector2(maxf(0.001,anchor.distance_to(endpoint)),2.0)
		rotation = anchor.direction_to(endpoint).angle()
	elif component == "tip":
		anchor += direction.normalized()*float(geometry.get("length",radius))
		contact_size = Vector2(8,8)
	var cell := Vector2(float(asset.get("cell_w",0)),float(asset.get("cell_h",0)))
	var pivot := _vec(asset.get("anchor_px",[cell.x/2,cell.y/2]))
	var bounds_values: Array = asset.get("vfx_bounds_px",[0,0,cell.x,cell.y])
	var bounds := Rect2(float(bounds_values[0]),float(bounds_values[1]),float(bounds_values[2]),float(bounds_values[3]))
	if cell.x <= 0 or cell.y <= 0 or bounds.size.x <= 0 or bounds.size.y <= 0: return _diagnostic(effect,"invalid_asset_geometry",str(layer.art_id))
	# Reused centered ally art is a forward path only for explicitly authored
	# line layers. Keep legacy projectile and target-contact pivots untouched.
	if shape == "line" and layer.get("forward_origin",false): pivot.x = bounds.position.x
	rotation += deg_to_rad(float(layer.get("rotation_offset_degrees",0.0))+float(layer.get("stage_rotation_degrees",0.0))*int(effect.get("stage_index",0))+float(layer.get("rotation_speed_degrees",0.0))*maxi(0,tick-int(effect.get("start_tick",0))))
	var scale := contact_size/bounds.size
	var local_rect := Rect2(-pivot,cell)
	var lifetime := maxi(1,int(effect.end_tick)-int(effect.start_tick))
	var age := maxi(0,tick-int(effect.start_tick))
	var progress := clampf(float(age)/lifetime,0.0,1.0)
	var animations: Dictionary = asset.get("animations",{})
	var frames: Array = animations.get("attack",{}).get("frames",[0])
	if frames.is_empty(): return _diagnostic(effect,"missing_frames",str(layer.art_id))
	var animation_duration := maxi(1,int(effect.get("animation_duration_ticks",lifetime)))
	var animation_age := maxi(0,tick-int(effect.get("animation_start_tick",effect.start_tick)))
	var animation_progress := fposmod(float(animation_age),float(animation_duration))/animation_duration if effect.get("animation_loop",false) else clampf(float(animation_age)/animation_duration,0.0,1.0)
	var frame := int(frames[mini(frames.size()-1,int(animation_progress*frames.size()))])
	var columns := maxi(1,int(asset.get("columns",1)))
	var region := Rect2(Vector2((frame%columns)*cell.x,(frame/columns)*cell.y),cell)
	# Ground aim and actual in-flight projectiles stay crisp; recovery alone fades.
	var alpha := 1.0 if effect.get("role","") in ["aim","projectile","area"] else clampf(1.0-progress,0.0,1.0)
	alpha *= clampf(float(effect.get("opacity",1.0)),0.0,1.0)
	var visual_bounds := _world_bounds(local_rect,anchor,rotation,scale)
	return {"effect_id":str(effect.get("effect_id","")),"attack_id":str(effect.get("attack_id","")),"cast_id":str(effect.get("cast_id","")),"evolution_id":str(effect.get("evolution_id","")),"stage_index":int(effect.get("stage_index",0)),"role":str(effect.get("role","")),"base_item_id":str(effect.get("base_item_id","")),"projectile_id":effect.get("projectile_id",null),"target_id":effect.get("target_id",null),"start_tick":int(effect.get("start_tick",0)),"asset_id":str(layer.art_id),"atlas_region":region,"world_anchor":anchor,"local_rect":local_rect,"rotation":rotation,"scale":scale,"alpha":alpha,"render_pass":str(layer.get("render_pass",effect.get("render_pass","world"))),"depth_y":anchor.y,"stable_id":str(effect.effect_id)+":"+str(index),"component":component,"contact_size":contact_size,"contact_geometry":geometry.duplicate(true),"world_bounds":visual_bounds,"intensity_tier":int(effect.get("intensity_tier",1)),"priority":int(effect.get("priority",0)),"source_sha256":str(asset.get("sha256",""))}
func _world_bounds(rect: Rect2, anchor: Vector2, rotation: float, scale: Vector2) -> Rect2:
	var points := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	var transformed := anchor+(_vec(points[0])*scale).rotated(rotation)
	var output := Rect2(transformed,Vector2.ZERO)
	for point in points: output = output.expand(anchor+(_vec(point)*scale).rotated(rotation))
	return output
func _diagnostic(effect: Dictionary, message: String, asset_id: String) -> Dictionary:
	return {"diagnostic":message,"asset_id":asset_id,"effect_id":effect.get("effect_id",""),"stable_id":str(effect.get("effect_id",""))+":diagnostic:"+asset_id,"render_pass":effect.get("render_pass","world"),"depth_y":_vec(effect.get("origin",Vector2.ZERO)).y}
func _pass_index(pass_name: String) -> int:
	return {"ground":0,"world":1,"contact_overlay":2}.get(pass_name,1)
func _vec(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2: return Vector2(float(value[0]),float(value[1]))
	return Vector2.ZERO
