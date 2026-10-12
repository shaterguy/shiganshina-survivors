class_name CityRender
extends RefCounted
# Pure command adapter. Asset lookup, animation time, hazards and actual drawing
# remain with WorldView. Every bounds rectangle here is origin-relative.
static func build(world_view: Dictionary, actors: Array, corpses: Array, projectiles: Array, camera_rect: Rect2) -> Dictionary:
	var ground: Array = []
	var upright: Array = []
	var markers: Array = []
	for chunk in world_view.get("chunks",[]):
		var tile_rect := Rect2(chunk.local_origin,Vector2(768,768))
		if tile_rect.intersects(camera_rect,true): ground.append({"kind":"chunk_ground","id":"ground:"+chunk.chunk_id,"position":chunk.local_origin,"bounds":tile_rect,"ground_variant":chunk.ground_variant})
		for prop in chunk.props:
			if prop.render_bounds.intersects(camera_rect,true): upright.append(_command(prop,prop.prop_id))
	for group in [{"namespace":"actor","items":actors},{"namespace":"corpse","items":corpses},{"namespace":"projectile","items":projectiles}]:
		for actor in group.items:
			var identity := _identity(actor,group.namespace)
			if not identity.ok: return {"ok":false,"error_code":"invalid_render_identity","ground":[],"upright":[],"visibility_markers":[]}
			var id: String = identity.id
			var command := _command(actor,id)
			command.source_id = identity.source_id
			var height: float = actor.get("visual_height",0)
			command.visual_height = height
			if height > 0:
				var shadow := Rect2(actor.position-Vector2(18,6),Vector2(36,12))
				if shadow.intersects(camera_rect,true): ground.append({"kind":"shadow","id":"shadow:"+id,"position":actor.position,"bounds":shadow})
				command.position.y -= height
				command.render_bounds.position.y -= height
			if command.render_bounds.intersects(camera_rect,true):
				upright.append(command)
				if actor.get("is_player",false): markers.append({"kind":"player_outline","id":"outline:"+id,"actor_id":id,"position":actor.position,"render_bounds":command.render_bounds,"occlusion_only":true})
	upright.sort_custom(func(a,b): return a.depth_y < b.depth_y or (a.depth_y == b.depth_y and a.id < b.id))
	ground.sort_custom(func(a,b): return a.id < b.id)
	markers.sort_custom(func(a,b): return a.id < b.id)
	return {"ground":ground,"upright":upright,"visibility_markers":markers}
static func _command(item: Dictionary, id: String) -> Dictionary:
	return {"id":id,"asset_id":item.asset_id,"position":item.position,"depth_y":float(item.get("depth_y",item.position.y)),"render_bounds":item.render_bounds,"pose":item.get("pose","idle")}

static func _identity(item: Dictionary, namespace_id: String) -> Dictionary:
	# One conversion boundary for Core IDs. Integral JSON numeric values use the
	# same identity as int IDs; strings stay distinct. Category prefixes prevent
	# actor/corpse/projectile collisions, including markers and shadows.
	var source_id = item.get("id",item.get("entity_id",item.get("projectile_id",null)))
	if source_id is String and not source_id.is_empty():
		return {"ok":true,"id":namespace_id+":s:"+source_id,"source_id":source_id}
	if source_id is int:
		return {"ok":true,"id":namespace_id+":i:"+str(source_id),"source_id":source_id}
	if source_id is float and is_finite(source_id) and source_id == floor(source_id) and absf(source_id) <= 9007199254740991.0:
		return {"ok":true,"id":namespace_id+":i:"+str(int(source_id)),"source_id":source_id}
	return {"ok":false}
