extends RefCounted
# Side-view walk, screen right is forward. No random numbers, accumulated time,
# torso warps, pose swaps, or whole-sprite displacement are used.
func default_config() -> Dictionary:
	return {
		"pelvis": [96.0, 149.0], "torso": [96.0, 149.0],
		"right_hip_offset": [6.0, 0.0], "left_hip_offset": [-6.0, 0.0],
		"right_shoulder": [108.0, 91.0], "left_shoulder": [87.0, 91.0],
		"thigh_length": 52.0, "shin_length": 51.0,
		"upper_arm_length": 33.0, "forearm_length": 33.0,
		"ground_y": 250.0, "ankle_height": 7.0,
		"stride": 40.0, "swing_height": 17.0, "stance_fraction": 0.6,
		"arm_swing": 25.0, "arm_drop": 57.0, "swing_foot_pitch": -0.12,
		"knee_bend": -1.0, "elbow_bend": -1.0,
		"body_bob_amplitude": 0.0, "body_bob_phase_offset": 0.0
	}

func as_vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func validate_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var defaults := default_config()
	for key in defaults:
		if not config.has(key):
			if key in ["body_bob_amplitude", "body_bob_phase_offset"]: continue
			errors.append("Missing gait field: " + key)
			continue
		if defaults[key] is Array:
			if not config[key] is Array or config[key].size() != 2:
				errors.append("Expected [x, y]: " + key)
			else:
				for coordinate in config[key]:
					if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):
						errors.append("Invalid coordinate: " + key)
		elif not (config[key] is float or config[key] is int) or not is_finite(float(config[key])):
			errors.append("Invalid number: " + key)
	if not errors.is_empty(): return errors
	for key in ["thigh_length", "shin_length", "upper_arm_length", "forearm_length", "stride", "swing_height", "arm_swing", "arm_drop"]:
		if float(config[key]) <= 0.0: errors.append("Must be positive: " + key)
	if float(config.stance_fraction) < 0.5 or float(config.stance_fraction) >= 0.9:
		errors.append("stance_fraction must be >= 0.5 and < 0.9")
	if float(config.ankle_height) < 0.0: errors.append("ankle_height must not be negative")
	if float(config.get("body_bob_amplitude", 0.0)) < 0.0: errors.append("body_bob_amplitude must not be negative")
	if not errors.is_empty(): return errors
	for key in ["knee_bend", "elbow_bend"]:
		if is_zero_approx(float(config[key])): errors.append("Nonzero bend direction required: " + key)
	# Conservative continuous bounds, not a finite set of samples that can miss extrema.
	var arm_min := float(config.arm_drop)
	var arm_max := Vector2(float(config.arm_drop), float(config.arm_swing)).length()
	if arm_min <= absf(float(config.upper_arm_length) - float(config.forearm_length)) + 0.00001 or arm_max >= float(config.upper_arm_length) + float(config.forearm_length) - 0.00001:
		errors.append("Continuous arm path is outside the two-bone reach interval")
	var bounds := continuous_leg_reach_bounds(config)
	for side in ["right", "left"]:
		if bounds[side].minimum <= absf(float(config.thigh_length) - float(config.shin_length)) + 0.00001 or bounds[side].maximum >= float(config.thigh_length) + float(config.shin_length) - 0.00001:
			errors.append("Continuous phase-coupled foot path is outside leg reach: " + side)

	return errors

func pose(phase: float, config: Dictionary = {}) -> Dictionary:
	var c: Dictionary = default_config() if config.is_empty() else config
	var p := fposmod(phase, 1.0)
	var displacement := Vector2(0.0, body_height_offset(p, c))
	var pelvis := as_vector(c.pelvis) + displacement
	return {
		"phase": p, "pelvis": pelvis, "torso": as_vector(c.torso) + displacement,
		"body_offset": displacement,
		"right_leg": leg(p, pelvis + as_vector(c.right_hip_offset), c, pelvis.x),
		"left_leg": leg(fposmod(p + 0.5, 1.0), pelvis + as_vector(c.left_hip_offset), c, pelvis.x),
		"right_arm": arm(p, as_vector(c.right_shoulder) + displacement, c),
		"left_arm": arm(fposmod(p + 0.5, 1.0), as_vector(c.left_shoulder) + displacement, c)
	}

func leg(phase: float, hip: Vector2, c: Dictionary, forward_axis_x: float) -> Dictionary:
	var duty := float(c.stance_fraction)
	var stride := float(c.stride)
	var contact := phase < duty
	var x: float
	var lift := 0.0
	var pitch := 0.0
	if contact:
		# Constant rearward stance velocity cancels forward actor movement.
		x = stride * (0.5 - phase / duty)
	else:
		var u := (phase - duty) / (1.0 - duty)
		# Cubic Hermite interpolation has the SAME velocity as stance at both ends.
		# The small natural toe-off/heel-strike overrun avoids a reversal snap.
		var tangent := -stride * (1.0 - duty) / duty
		x = _hermite(-stride * 0.5, stride * 0.5, tangent, tangent, u)
		var envelope := pow(sin(PI * u), 2.0)
		lift = float(c.swing_height) * envelope
		pitch = float(c.swing_foot_pitch) * envelope
	var target := Vector2(forward_axis_x + x, float(c.ground_y) - float(c.ankle_height) - lift)
	var solved := solve_two_bone(hip, target, float(c.thigh_length), float(c.shin_length), float(c.knee_bend))
	return {"hip": hip, "knee": solved.joint, "ankle": solved.end,
		"contact": contact, "foot_angle": pitch, "phase": phase, "clamped": solved.clamped}

func arm(phase: float, shoulder: Vector2, c: Dictionary) -> Dictionary:
	# Shift the cosine zero crossings to the center of the stance and swing.
	# This keeps same-side arm/leg opposition even with a double-support phase.
	var shift := (float(c.stance_fraction) - 0.5) * 0.5
	var swing := -cos(TAU * (phase - shift))
	var wrist := shoulder + Vector2(float(c.arm_swing) * swing, float(c.arm_drop))
	var solved := solve_two_bone(shoulder, wrist, float(c.upper_arm_length), float(c.forearm_length), float(c.elbow_bend))
	return {"shoulder": shoulder, "elbow": solved.joint, "wrist": solved.end,
		"swing": swing, "clamped": solved.clamped}

func solve_two_bone(root: Vector2, target: Vector2, upper: float, lower: float, bend: float) -> Dictionary:
	var delta := target - root
	var distance := delta.length()
	var minimum := absf(upper - lower) + 0.00001
	var maximum := upper + lower - 0.00001
	var reachable_distance := clampf(distance, minimum, maximum)
	var direction := delta / distance if distance > 0.000001 else Vector2.DOWN
	var along := (upper * upper - lower * lower + reachable_distance * reachable_distance) / (2.0 * reachable_distance)
	var perpendicular := sqrt(maxf(0.0, upper * upper - along * along))
	var elbow := root + direction * along + Vector2(-direction.y, direction.x) * perpendicular * signf(bend)
	return {"root": root, "joint": elbow, "end": root + direction * reachable_distance,
		"clamped": not is_equal_approx(distance, reachable_distance)}

func _hermite(a: float, b: float, tangent_a: float, tangent_b: float, u: float) -> float:
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * a + (u3 - 2.0 * u2 + u) * tangent_a + (-2.0 * u3 + 3.0 * u2) * b + (u3 - u2) * tangent_b

func motion_contract(config: Dictionary, frame_count: int, fps: float) -> Dictionary:
	var cycle_distance := float(config.stride) / float(config.stance_fraction)
	var duration := float(frame_count) / fps
	var mapping: Array[Dictionary] = []
	for index in range(frame_count):
		var phase := float(index) / float(frame_count)
		mapping.append({"frame": index, "phase": phase, "distance_px": phase * cycle_distance,
			"right_contact": phase < float(config.stance_fraction),
			"left_contact": fposmod(phase + 0.5, 1.0) < float(config.stance_fraction)})
	return {"cycle_distance_px": cycle_distance, "stance_travel_px": float(config.stride),
		"stance_fraction": float(config.stance_fraction), "cycle_duration_seconds": duration,
		"reference_speed_px_per_second": cycle_distance / duration,
		"frame_count": frame_count, "reference_fps": fps, "frame_mapping": mapping,
		"body_translation": {"amplitude_px": float(config.get("body_bob_amplitude", 0.0)),
			"phase_offset_cycles": fposmod(float(config.get("body_bob_phase_offset", 0.0)), 1.0), "cycles_per_walk": 2,
			"mean_pelvis_y": float(config.pelvis[1]), "fixed_ground_y": float(config.ground_y),
			"formula": "body_dy = amplitude * cos(4 * PI * (wrapped_distance_phase - phase_offset)); apply to body roots only, never feet"},
		"world_cycle_distance": "cycle_distance_px * sprite_display_scale",
		"phase_from_distance": "positive_mod(distance_travelled / world_cycle_distance, 1)",
		"frame_from_phase": "floor(phase * frame_count) modulo frame_count",
		"foot_lock": "During stance, forward root displacement equals the rearward local foot displacement. Use travelled distance, not arbitrary fixed FPS.",
		"baked_frame_limit": "Continuous IK has exact stance lock. Selecting %d discrete PNGs introduces at most one frame-step of quantization; do not claim subpixel-perfect runtime foot lock." % frame_count}

func body_height_offset(phase: float, c: Dictionary) -> float:
	return float(c.get("body_bob_amplitude", 0.0)) * cos(2.0 * TAU * (fposmod(phase, 1.0) - fposmod(float(c.get("body_bob_phase_offset", 0.0)), 1.0)))

func continuous_leg_reach_bounds(c: Dictionary, partitions: int = 256) -> Dictionary:
	# Every interval contains ALL continuous phases, not just sampled endpoints.
	# Split at both legs' wrap/contact boundaries before bounding polynomial/trig extrema.
	var cuts: Array[float] = [0.0, 0.5, 1.0, float(c.stance_fraction), fposmod(float(c.stance_fraction) - 0.5, 1.0)]
	for i in range(1, maxi(1, partitions)): cuts.append(float(i) / float(maxi(1, partitions)))
	cuts.sort()
	var result := {"partitions": maxi(1, partitions), "method": "continuous phase intervals with analytic Hermite/cosine extrema and outward numerical padding"}
	for side in ["right", "left"]:
		var lower := INF
		var upper := 0.0
		var offset := 0.0 if side == "right" else 0.5
		var hip: Array = c[side + "_hip_offset"]
		for i in range(cuts.size() - 1):
			if cuts[i + 1] - cuts[i] < 0.000000000001: continue
			var box := _relative_leg_box(c, cuts[i], cuts[i + 1], offset, float(hip[0]), float(hip[1]))
			var dx := maxf(absf(box[0]), absf(box[1]))
			var dy := maxf(absf(box[2]), absf(box[3]))
			upper = maxf(upper, sqrt(dx * dx + dy * dy))
			var near_x := 0.0 if box[0] <= 0.0 and box[1] >= 0.0 else minf(absf(box[0]), absf(box[1]))
			var near_y := 0.0 if box[2] <= 0.0 and box[3] >= 0.0 else minf(absf(box[2]), absf(box[3]))
			lower = minf(lower, sqrt(near_x * near_x + near_y * near_y))
		# Godot's Vector2 pose arithmetic is single precision; widen the double-precision bound.
		var padding := maxf(1.0, upper) * 0.000001
		result[side] = {"minimum": maxf(0.0, lower - padding), "maximum": upper + padding, "numerical_padding": padding}
	return result

func _relative_leg_box(c: Dictionary, a: float, b: float, offset: float, hip_x: float, hip_y: float) -> Array[float]:
	var cycle := floorf((a + b) * 0.5 + offset)
	var q0 := a + offset - cycle
	var q1 := b + offset - cycle
	var duty := float(c.stance_fraction)
	var stride := float(c.stride)
	var x_low: float
	var x_high: float
	var lift_low := 0.0
	var lift_high := 0.0
	if (q0 + q1) * 0.5 < duty:
		x_low = stride * (0.5 - q1 / duty)
		x_high = stride * (0.5 - q0 / duty)
	else:
		var u0 := (q0 - duty) / (1.0 - duty)
		var u1 := (q1 - duty) / (1.0 - duty)
		var range_x := _swing_x_interval(stride, duty, u0, u1)
		x_low = range_x[0]
		x_high = range_x[1]
		var lift_cos := _cos_interval(TAU * u0, TAU * u1)
		lift_low = float(c.swing_height) * 0.5 * (1.0 - lift_cos[1])
		lift_high = float(c.swing_height) * 0.5 * (1.0 - lift_cos[0])
	var bob_offset := fposmod(float(c.get("body_bob_phase_offset", 0.0)), 1.0)
	var body_cos := _cos_interval(2.0 * TAU * (a - bob_offset), 2.0 * TAU * (b - bob_offset))
	var amplitude := float(c.get("body_bob_amplitude", 0.0))
	var baseline := float(c.ground_y) - float(c.ankle_height) - float(c.pelvis[1]) - hip_y
	return [x_low - hip_x, x_high - hip_x,
		baseline - lift_high - amplitude * body_cos[1], baseline - lift_low - amplitude * body_cos[0]]

func _swing_x_interval(stride: float, duty: float, u0: float, u1: float) -> Array[float]:
	var tangent := -stride * (1.0 - duty) / duty
	var start := _hermite(-stride * 0.5, stride * 0.5, tangent, tangent, u0)
	var finish := _hermite(-stride * 0.5, stride * 0.5, tangent, tangent, u1)
	var low := minf(start, finish)
	var high := maxf(start, finish)
	var a := -6.0 * stride + 6.0 * tangent
	var b := 6.0 * stride - 6.0 * tangent
	var discriminant := b * b - 4.0 * a * tangent
	for u in [(-b + sqrt(discriminant)) / (2.0 * a), (-b - sqrt(discriminant)) / (2.0 * a)]:
		if u >= u0 and u <= u1:
			var value := _hermite(-stride * 0.5, stride * 0.5, tangent, tangent, u)
			low = minf(low, value)
			high = maxf(high, value)
	return [low, high]

func _cos_interval(a: float, b: float) -> Array[float]:
	var low := minf(cos(a), cos(b))
	var high := maxf(cos(a), cos(b))
	for k in range(ceili(a / PI), floori(b / PI) + 1):
		var value := 1.0 if posmod(k, 2) == 0 else -1.0
		low = minf(low, value)
		high = maxf(high, value)
	return [low, high]
