extends "res://game/world/city_navigation.gd"
func _build_grid(chunk: Dictionary, clearance: int) -> Dictionary:
	_grid_builds += 1
	var flags := PackedByteArray()
	flags.resize(576)
	for id in 576:
		var point: Vector2 = _center(id,chunk.local_origin)
		flags[id] = 1
		for prop in chunk.props:
			if prop.collision_mask == 0: continue
			var box: Rect2 = prop.ground_footprint.grow(clearance)
			if point.x > box.position.x and point.x < box.end.x and point.y > box.position.y and point.y < box.end.y: flags[id] = 0; break
	return {"chunk_id":chunk.chunk_id,"revision":chunk.geometry_revision,"local_origin":chunk.local_origin,"flags":flags}
