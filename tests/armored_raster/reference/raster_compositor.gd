extends RefCounted
# Actual raster source parts are composed through affine bone transforms on CPU.
# Godot's dummy headless rendering driver is intentionally not used for screenshots.
const REQUIRED_PARTS := ["torso", "right_upper_arm", "right_forearm", "left_upper_arm", "left_forearm", "right_thigh", "right_shin", "right_foot", "left_thigh", "left_shin", "left_foot"]
const DRAW_ORDER := ["left_upper_arm", "left_forearm", "left_thigh", "left_shin", "left_foot", "torso", "right_thigh", "right_shin", "right_foot", "pelvis_cover", "right_upper_arm", "right_forearm"]
const GAIT := preload("res://tests/armored_raster/reference/gait_math.gd")

func validate_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _valid_vector(config.get("canvas", null)) or _vector(config.get("canvas", [0, 0])) != Vector2(192, 256): errors.append("canvas must be [192, 256]")
	if not config.get("frames", 0) is float and not config.get("frames", 0) is int:
		errors.append("frames must be an integer")
	elif not is_finite(float(config.get("frames", 0))) or float(config.get("frames", 0)) != floor(float(config.get("frames", 0))) or int(config.get("frames", 0)) < 4 or int(config.get("frames", 0)) % 2 != 0:
		errors.append("frames must be an even integer >= 4")
	if not config.get("fps", 0) is float and not config.get("fps", 0) is int:
		errors.append("fps must be numeric")
	elif not _positive_number(config.get("fps", 0)): errors.append("fps must be positive and finite")
	if not config.get("gait", null) is Dictionary:
		errors.append("gait object is required")
	else:
		errors.append_array(GAIT.new().validate_config(config.gait))
	if not config.get("parts", null) is Dictionary:
		errors.append("parts object is required")
		return errors
	for name in REQUIRED_PARTS:
		if not config.parts.has(name): errors.append("Missing original part: " + name)
	for name in config.parts:
		if not name in DRAW_ORDER:
			errors.append("Unknown part: " + name)
			continue
		var part = config.parts[name]
		if not part is Dictionary:
			errors.append("Part must be an object: " + name)
			continue
		if not part.get("path", "") is String or not str(part.get("path", "")).to_lower().ends_with(".png"):
			errors.append("Part requires original PNG path: " + name)
		if not _valid_vector(part.get("pivot", null)): errors.append("Part requires pivot [x, y]: " + name)
		if name.ends_with("_foot") or name in ["torso", "pelvis_cover"]:
			if not _positive_number(part.get("scale", 1.0)): errors.append("Part scale must be positive: " + name)
		else:
			if not _valid_vector(part.get("native_axis", [0, 1])) or _vector(part.get("native_axis", [0, 1])).length() < 0.00001:
				errors.append("Nonzero native_axis required: " + name)
			if not _positive_number(part.get("native_length", 0)): errors.append("Positive native_length required: " + name)
			if part.has("width_scale") and not _positive_number(part.width_scale): errors.append("Positive width_scale required: " + name)
		if part.has("modulate"):
			if not part.modulate is Array or part.modulate.size() != 4:
				errors.append("modulate must be [r, g, b, a]: " + name)
			else:
				for channel in part.modulate:
					if not (channel is float or channel is int) or not is_finite(float(channel)) or float(channel) < 0.0 or float(channel) > 1.0:
						errors.append("modulate channels must be finite numbers in [0, 1]: " + name)
	return errors

func _valid_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for coordinate in value:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)): return false
	return true

func _positive_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0

func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func bone_transform(pivot: Vector2, native_axis: Vector2, native_length: float, joint: Vector2, next_joint: Vector2, width_scale: float = -1.0) -> Transform2D:
	var native_direction := native_axis.normalized()
	var native_across := Vector2(native_direction.y, -native_direction.x)
	var target_direction := (next_joint - joint).normalized()
	var target_across := Vector2(target_direction.y, -target_direction.x)
	var length_scale := joint.distance_to(next_joint) / native_length
	var across_scale := length_scale if width_scale < 0.0 else width_scale
	var column_x := target_across * native_across.x * across_scale + target_direction * native_direction.x * length_scale
	var column_y := target_across * native_across.y * across_scale + target_direction * native_direction.y * length_scale
	var transform := Transform2D(column_x, column_y, Vector2.ZERO)
	transform.origin = joint - transform.basis_xform(pivot)
	return transform

func part_transform(name: String, part: Dictionary, pose: Dictionary) -> Transform2D:
	var pivot := _vector(part.pivot)
	if name in ["torso", "pelvis_cover"] or name.ends_with("_foot"):
		var angle := 0.0
		var anchor: Vector2 = pose.torso if name == "torso" else pose.pelvis
		if name.ends_with("_foot"):
			var leg: Dictionary = pose[name.trim_suffix("_foot") + "_leg"]
			anchor = leg.ankle
			angle = leg.foot_angle
		var transform := Transform2D(angle, Vector2.ZERO).scaled(Vector2.ONE * float(part.get("scale", 1.0)))
		transform.origin = anchor - transform.basis_xform(pivot)
		return transform
	var side := "right" if name.begins_with("right_") else "left"
	var joint: Vector2
	var next_joint: Vector2
	if name.ends_with("_thigh"):
		joint = pose[side + "_leg"].hip
		next_joint = pose[side + "_leg"].knee
	elif name.ends_with("_shin"):
		joint = pose[side + "_leg"].knee
		next_joint = pose[side + "_leg"].ankle
	elif name.ends_with("_upper_arm"):
		joint = pose[side + "_arm"].shoulder
		next_joint = pose[side + "_arm"].elbow
	else:
		joint = pose[side + "_arm"].elbow
		next_joint = pose[side + "_arm"].wrist
	return bone_transform(pivot, _vector(part.get("native_axis", [0, 1])), float(part.native_length), joint, next_joint, float(part.get("width_scale", -1.0)))

func compose(config: Dictionary, pose: Dictionary, images: Dictionary) -> Image:
	var frame := Image.create(192, 256, false, Image.FORMAT_RGBA8)
	frame.fill(Color.TRANSPARENT)
	for name in DRAW_ORDER:
		if not config.parts.has(name): continue
		var part: Dictionary = config.parts[name]
		var tint := Color.WHITE
		if part.has("modulate"): tint = Color(part.modulate[0], part.modulate[1], part.modulate[2], part.modulate[3])
		blit_transformed(frame, images[name], part_transform(name, part, pose), tint)
	return frame

func blit_transformed(destination: Image, source: Image, transform: Transform2D, modulate: Color = Color.WHITE) -> void:
	var bounds := Rect2(transform * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(source.get_width(), 0), Vector2(0, source.get_height()), Vector2(source.get_width(), source.get_height())]:
		bounds = bounds.expand(transform * corner)
	var inverse := transform.affine_inverse()
	var min_x := maxi(0, int(floor(bounds.position.x)))
	var min_y := maxi(0, int(floor(bounds.position.y)))
	var max_x := mini(destination.get_width(), int(ceil(bounds.end.x)))
	var max_y := mini(destination.get_height(), int(ceil(bounds.end.y)))
	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			# Pixel-center inverse sampling avoids forward-mapping holes.
			var sample := inverse * Vector2(x + 0.5, y + 0.5)
			var sx := int(floor(sample.x))
			var sy := int(floor(sample.y))
			if sx < 0 or sy < 0 or sx >= source.get_width() or sy >= source.get_height(): continue
			var foreground := source.get_pixel(sx, sy) * modulate
			if foreground.a <= 0.0: continue
			if foreground.a >= 1.0:
				destination.set_pixel(x, y, foreground)
				continue
			var background := destination.get_pixel(x, y)
			var alpha := foreground.a + background.a * (1.0 - foreground.a)
			var behind := background.a * (1.0 - foreground.a)
			destination.set_pixel(x, y, Color((foreground.r * foreground.a + background.r * behind) / alpha,
				(foreground.g * foreground.a + background.g * behind) / alpha,
				(foreground.b * foreground.a + background.b * behind) / alpha, alpha))
