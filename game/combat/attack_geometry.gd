class_name AttackGeometry
extends RefCounted
static func overlaps(record: Dictionary, point: Vector2, body_radius := 0.0) -> bool:
	var origin := Vector2(record.origin[0],record.origin[1])
	var offset := point-origin
	var shape := str(record.shape)
	if shape == "circle": return offset.length() <= float(record.radius)+body_radius
	var direction_data: Array = record.get("direction",[1.0,0.0])
	var direction := Vector2(direction_data[0],direction_data[1]).normalized()
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	if shape == "line":
		var projection := clampf(offset.dot(direction),0.0,float(record.length))
		return offset.distance_to(direction*projection) <= float(record.width)*0.5+body_radius
	if shape == "sector":
		var radius := float(record.radius)
		if offset.length() > radius+body_radius: return false
		if offset.length() <= body_radius: return true
		var half_arc := deg_to_rad(float(record.get("arc_degrees",record.get("angle_degrees",90.0)))*0.5)
		var angle := absf(direction.angle_to(offset))
		if angle <= half_arc: return true
		# Circle-body overlap with the two radial edges matches the visible sector.
		for sign_value in [-1.0,1.0]:
			var edge := direction.rotated(half_arc*sign_value)
			var along := clampf(offset.dot(edge),0.0,radius)
			if offset.distance_to(edge*along) <= body_radius: return true
	return false
