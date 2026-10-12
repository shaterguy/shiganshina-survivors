extends RefCounted
const REFERENCE = preload("res://tests/armored_raster/reference/raster_compositor.gd")
const PACKET_PATH = "res://game/presentation/armored/armored_pose_packet.gd"
const ORDER = ["left_upper_arm", "left_forearm", "left_thigh", "left_shin", "left_foot", "right_thigh", "right_shin", "right_foot", "posterior_underlap", "head_seam_underlap", "neck", "girdle", "torso", "head", "right_upper_arm", "plate", "right_forearm"]

func v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

func vectors(value):
	if value is Dictionary:
		var result = {}
		for key in value: result[key] = vectors(value[key])
		return result
	if value is Array and value.size() == 2 and (value[0] is float or value[0] is int): return v(value)
	return value

func same_transform(a: Transform2D, b: Transform2D) -> bool:
	return a.x.distance_to(b.x) < 0.00001 and a.y.distance_to(b.y) < 0.00001 and a.origin.distance_to(b.origin) < 0.0001

func run(t) -> void:
	t.check(FileAccess.file_exists(PACKET_PATH), "pure runtime pose compiler exists")
	if not FileAccess.file_exists(PACKET_PATH): return
	var script = load(PACKET_PATH)
	t.check(script != null and script.can_instantiate(), "pure compiler loads")
	if script == null or not script.can_instantiate(): return
	var compiler = script.new()
	var registration = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/rig/armored_runtime_v1/registration.json"))
	var golden = JSON.parse_string(FileAccess.get_file_as_string("res://tests/armored_raster/golden_rows.json"))
	var reference = REFERENCE.new()
	for fixture in golden.rows:
		var row: Dictionary = fixture.row
		var original_row = row.duplicate(true)
		var original_registration = registration.duplicate(true)
		var packet: Dictionary = compiler.compile_pose(row, registration)
		t.check(packet.ok, "golden compiles: " + fixture.fixture_id)
		if not packet.ok: continue
		t.check(row == original_row and registration == original_registration, "compile is pure: " + fixture.fixture_id)
		t.check(packet.pose_tick == row.core_tick, "same accepted pose tick: " + fixture.fixture_id)
		t.check(packet.has("support_status") and packet.support_status == {"left_contact": row.pose.left_leg.contact, "right_contact": row.pose.right_leg.contact}, "saved support status accompanies immutable packet")
		t.check(packet.commands.size() == ORDER.size(), "whole packet contains all layers: " + fixture.fixture_id)
		var pose = vectors(row.pose)
		var torso = Transform2D(pose.torso_angle, Vector2.ZERO).scaled(Vector2.ONE * .085)
		torso.origin = pose.pelvis - torso.basis_xform(Vector2(210, 1175))
		var head = Transform2D(row.head_relative_angle, Vector2.ZERO)
		head.origin = v(row.head_control_source) - head.basis_xform(Vector2(866, 610))
		var combined = Rect2()
		var has_bounds = false
		for index in range(packet.commands.size()):
			var command: Dictionary = packet.commands[index]
			var name: String = ORDER[index]
			t.check(command.part_id == name and command.layer == index, "frozen layer order: " + name)
			var expected = torso
			if golden.parts.has(name): expected = reference.part_transform(name, golden.parts[name], pose)
			elif name in ["head", "head_seam_underlap"]: expected = torso * head
			elif name == "plate": expected = torso * Transform2D(0, v(row.near_plate_offset_source))
			var part: Dictionary = registration.parts[name]
			if name == "neck":
				t.check(same_transform(command.transform, expected), "mesh torso affine agrees with frozen compositor")
				t.check(command.vertices.size() == row.mesh.neck.destinations.size(), "complete mesh vertex count")
				for i in range(command.vertices.size()):
					t.check(command.vertices[i].distance_to(v(row.mesh.neck.destinations[i])) < 0.0001, "frozen mesh destination")
					var expected_uv = (v(golden.meshes.neck.points[i]) - v(part.source_offset)) / v(part.packed_size)
					t.check(command.uvs[i].distance_to(expected_uv) < 0.000001, "trim offset preserves original mesh UV")
				t.check(command.indices.size() == golden.meshes.neck.triangles.size() * 3, "mesh triangles retained")
			else:
				expected = expected * Transform2D(0, v(part.source_offset))
				t.check(same_transform(command.transform, expected), "frozen affine with trim offset: " + name)
				t.check(command.vertices.is_empty() and command.uvs.is_empty(), "affine piece has no deformation: " + name)
			if not has_bounds: combined = command.bounds; has_bounds = true
			else: combined = combined.merge(command.bounds)
		t.check(packet.bounds.is_equal_approx(combined), "packet native bounds retain un-clipped alpha/mesh support")
		t.check(packet.canvas_contained == Rect2(0, 0, 288, 288).encloses(combined), "outside-canvas status is explicit")
		packet.commands[0].part_id = "mutated-result"
		t.check(compiler.compile_pose(row, registration).commands[0].part_id == ORDER[0], "returned packets own commands independently")
	var row: Dictionary = golden.rows[0].row.duplicate(true)
	var bad = row.duplicate(true)
	bad.mesh.neck.folded_triangles = [0]
	assert_rejected(t, compiler.compile_pose(bad, registration), "reported fold")
	bad = row.duplicate(true)
	bad.mesh.neck.destinations[1] = bad.mesh.neck.destinations[0]
	assert_rejected(t, compiler.compile_pose(bad, registration), "geometric fold/degeneracy despite empty reported folds")
	bad = row.duplicate(true)
	bad.mesh.neck.destinations.pop_back()
	assert_rejected(t, compiler.compile_pose(bad, registration), "incomplete mesh")
	bad = row.duplicate(true)
	bad.pose.right_arm.wrist[0] += 4
	assert_rejected(t, compiler.compile_pose(bad, registration), "fixed forearm length")
	bad = row.duplicate(true)
	bad.source_scale = .075
	assert_rejected(t, compiler.compile_pose(bad, registration), "stale source scale")
	var bad_registration = registration.duplicate(true)
	bad_registration.parts.erase("right_forearm")
	assert_rejected(t, compiler.compile_pose(row, bad_registration), "missing required source")
	bad_registration = registration.duplicate(true)
	bad_registration.meshes.neck.triangles[0][0] = 999999
	assert_rejected(t, compiler.compile_pose(row, bad_registration), "bad mesh index")
	bad_registration = registration.duplicate(true)
	bad_registration.parts.right_foot.scale = .126
	assert_rejected(t, compiler.compile_pose(row, bad_registration), "fixed foot scale")
	bad_registration = registration.duplicate(true)
	bad_registration.parts.right_upper_arm.native_length += 1
	bad_registration.parts.right_upper_arm.fixed_width_scale = 39.0 / bad_registration.parts.right_upper_arm.native_length
	assert_rejected(t, compiler.compile_pose(row, bad_registration), "fixed native length even with self-consistent forged width")
	bad_registration = registration.duplicate(true)
	bad_registration.layer_order.reverse()
	assert_rejected(t, compiler.compile_pose(row, bad_registration), "fixed layer order")
	bad = row.duplicate(true)
	bad.head_control_source[0] = 1e300
	assert_rejected(t, compiler.compile_pose(bad, registration), "finite float64 overflowing actual Vector2 representation")
	bad = row.duplicate(true)
	bad.core_tick = 1e30
	assert_rejected(t, compiler.compile_pose(bad, registration), "tick overflowing integer conversion")
	bad = row.duplicate(true)
	bad.core_tick = 2147483648
	assert_rejected(t, compiler.compile_pose(bad, registration), "tick beyond actual Core MAX_COUNTER")
	bad = row.duplicate(true)
	bad.core_tick = 2147483647
	var maximum_tick = compiler.compile_pose(bad, registration)
	t.check(maximum_tick.ok and maximum_tick.pose_tick == 2147483647, "actual Core MAX_COUNTER remains valid without wrapping")
	bad_registration = registration.duplicate(true)
	bad_registration.parts.right_upper_arm.width_scale = 1.0
	bad_registration.parts.right_upper_arm.fixed_width_scale = 1.0
	assert_rejected(t, compiler.compile_pose(row, bad_registration), "jointly forged width fields cannot redefine approved width")
	bad = row.duplicate(true)
	for field in ["pelvis", "torso"]: bad.pose[field][0] += 500
	for side in ["left", "right"]:
		for field in ["hip", "knee", "ankle"]: bad.pose[side + "_leg"][field][0] += 500
		for field in ["shoulder", "elbow", "wrist"]: bad.pose[side + "_arm"][field][0] += 500
	var outside = compiler.compile_pose(bad, registration)
	t.check(outside.ok and not outside.canvas_contained and outside.bounds.end.x > 288, "out-of-canvas support is never silently clipped")
	t.check(not outside.outside_canvas.is_empty() and outside.quality_status == "HOLD", "out-of-canvas support has a named quality hold")
	t.check(outside.outside_canvas[0].has("source_witnesses"), "out-of-canvas diagnosis identifies original source-alpha support")
	t.check(golden.held_face_reach > golden.shoulder_limit, "EXPECTED QUALITY HOLD: strict face source reach 72.6571568 exceeds shoulder72")
	t.check(registration.quality_holds.face_source_corner_reach.status == "HOLD", "inherited strict clearance failure is retained")

func assert_rejected(t, packet: Dictionary, label: String) -> void:
	t.check(not packet.ok and not packet.reason.is_empty(), "reject " + label)
	t.check(packet.commands.is_empty() and packet.bounds == Rect2(), "atomic empty rejection: " + label)
