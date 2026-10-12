extends RefCounted
## Pure frozen-row compiler. No source loading, Core writes, renderer, or cache.
## A mathematical packet can carry a quality HOLD. `ok` means structurally
## valid, not approved artwork, native-pixel parity, or product activation.
const ORDER = ["left_upper_arm", "left_forearm", "left_thigh", "left_shin", "left_foot", "right_thigh", "right_shin", "right_foot", "posterior_underlap", "head_seam_underlap", "neck", "girdle", "torso", "head", "right_upper_arm", "plate", "right_forearm"]
const CANVAS = Rect2(0, 0, 288, 288)
const BONE_EPSILON = 0.001 # Float32 endpoint roundoff only; not IK stretching.
const MAX_COUNTER = 2147483647 # Same accepted counter ceiling as Core.
const LIMB_GEOMETRY = {
	"right_upper_arm": {"pivot": [166, 43], "axis": [-104, 263], "length": 282.81619472724685},
	"right_forearm": {"pivot": [60, 25], "axis": [3, 186], "length": 186.02419197512995},
	"left_upper_arm": {"pivot": [33, 29], "axis": [74, 256], "length": 266.48076853686837},
	"left_forearm": {"pivot": [63, 29], "axis": [27, 197], "length": 198.84164553734712},
	"right_thigh": {"pivot": [56, 27], "axis": [59, 259], "length": 265.63508804372964},
	"right_shin": {"pivot": [84, 21], "axis": [11, 252], "length": 252.23996511258878},
	"left_thigh": {"pivot": [133, 26], "axis": [-68, 260], "length": 268.7452325158532},
	"left_shin": {"pivot": [62, 24], "axis": [-4, 253], "length": 253.03161857759991},
	"right_foot": {"pivot": [61, 24], "scale": .125},
	"left_foot": {"pivot": [63, 26], "scale": .13876146788990826},
}

func compile_pose(row: Dictionary, registration: Dictionary) -> Dictionary:
	var error = _validate_registration(registration)
	if not error.is_empty(): return _reject(error)
	error = _validate_row(row, registration)
	if not error.is_empty(): return _reject(error)
	return _compile_checked(row,registration)

func _compile_checked(row: Dictionary, registration: Dictionary) -> Dictionary:
	var pose: Dictionary = row.pose
	var torso = Transform2D(float(pose.torso_angle), Vector2.ZERO).scaled(Vector2.ONE * float(row.source_scale))
	torso.origin = _v(pose.pelvis) - torso.basis_xform(_v(row.source_hip))
	var head = Transform2D(float(row.head_relative_angle), Vector2.ZERO)
	head.origin = _v(row.head_control_source) - head.basis_xform(_v(registration.head_pivot_source))
	var commands: Array[Dictionary] = []
	var outside: Array[Dictionary] = []
	var total_bounds = Rect2()
	var first = true
	for layer in range(ORDER.size()):
		var name: String = ORDER[layer]
		var part: Dictionary = registration.parts[name]
		var original_transform = torso
		if name.begins_with("left_") or name.begins_with("right_"):
			original_transform = _limb_transform(name, part, pose)
		elif name in ["head", "head_seam_underlap"]:
			original_transform = torso * head
		elif name == "plate":
			original_transform = torso * Transform2D(0, _v(row.near_plate_offset_source))
		if not original_transform.is_finite(): return _reject("command_source_transform_nonfinite:" + name)
		var command = {"part_id": name, "layer": layer, "transform": original_transform,
			"vertices": PackedVector2Array(), "uvs": PackedVector2Array(),
			"indices": PackedInt32Array(), "modulate": Color.WHITE,
			"source_offset": _v(part.source_offset), "source_transform": original_transform,
			"texture_size": _v(part.packed_size), "source_size": _v(part.original_size),
			"bounds": Rect2()}
		var support = PackedVector2Array()
		var witnesses: Array[Dictionary] = []
		if name == "neck":
			var mesh: Dictionary = registration.meshes.neck
			for index in range(mesh.points.size()):
				var source = _v(mesh.points[index])
				var destination = _v(row.mesh.neck.destinations[index])
				command.vertices.append(destination)
				var uv = (source - _v(part.source_offset)) / _v(part.packed_size)
				if not uv.is_finite(): return _reject("command_uv_nonfinite:" + name)
				command.uvs.append(uv)
				var world = original_transform * destination
				if not world.is_finite(): return _reject("command_mesh_point_nonfinite:" + name)
				support.append(world)
				if not _inside_canvas(world):
					witnesses.append({"mesh_vertex": index, "source_point": source, "destination": world, "kind": "mesh_geometry_not_alpha_proof"})
			for triangle in mesh.triangles:
				for index in triangle: command.indices.append(int(index))
		else:
			command.transform = original_transform * Transform2D(0, _v(part.source_offset))
			if not command.transform.is_finite(): return _reject("command_transform_nonfinite:" + name)
			for point in part.alpha_support_hull:
				var destination = original_transform * _v(point.point)
				if not destination.is_finite(): return _reject("command_alpha_point_nonfinite:" + name)
				support.append(destination)
				if not _inside_canvas(destination):
					witnesses.append({"source_point": _v(point.point), "source_pixel": _v(point.pixel), "alpha": int(point.alpha), "destination": destination, "kind": "nonzero_alpha_pixel_cell"})
		command.bounds = _bounds(support)
		if not command.bounds.position.is_finite() or not command.bounds.size.is_finite(): return _reject("command_bounds_nonfinite:" + name)
		if first: total_bounds = command.bounds; first = false
		else: total_bounds = total_bounds.merge(command.bounds)
		if not total_bounds.position.is_finite() or not total_bounds.size.is_finite(): return _reject("packet_bounds_nonfinite")
		if not CANVAS.encloses(command.bounds):
			outside.append({"part_id": name, "bounds": command.bounds, "source_witnesses": witnesses})
		commands.append(command)
	return {"ok": true, "reason": "", "commands": commands, "bounds": total_bounds,
		"pose_tick": int(row.core_tick), "pose_id": str(row.id), "source_state": str(row.sequence_phase),
		"support_status": {"left_contact": pose.left_leg.contact, "right_contact": pose.right_leg.contact},
		"canvas": Vector2(288, 288), "anchor_px": Vector2(144, 280), "anatomical_ground_y": 278,
		"canvas_contained": outside.is_empty(), "outside_canvas": outside,
		"quality_status": "HOLD", "quality_holds": registration.quality_holds.duplicate(true),
		"native_gpu_verified": false, "final_export_allowed": false}

## A per-actor owner can validate static registration once. No global memo,
## caller-owned registration reference, row cache, clock or skipped row checks.
func prepare_registration(registration: Dictionary) -> Dictionary:
	var error := _validate_registration(registration)
	if not error.is_empty(): return {"ok":false,"reason":error}
	return {"ok":true,"session":PreparedRegistration.new(self,registration)}

class PreparedRegistration extends RefCounted:
	var _compiler
	var _registration: Dictionary
	func _init(compiler, registration: Dictionary) -> void:
		_compiler=compiler
		_registration=registration.duplicate(true)
	func compile_pose(row: Dictionary) -> Dictionary:
		var error: String = _compiler._validate_row(row,_registration)
		if not error.is_empty(): return _compiler._reject(error)
		return _compiler._compile_checked(row,_registration)

func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "commands": [], "bounds": Rect2(), "pose_tick": -1,
		"canvas_contained": false, "outside_canvas": [], "quality_status": "ERROR",
		"native_gpu_verified": false, "final_export_allowed": false}

func _validate_registration(registration: Dictionary) -> String:
	if not _vector(registration.get("canvas")) or _v(registration.canvas) != Vector2(288, 288): return "registration_canvas"
	if not _vector(registration.get("anchor_px")) or _v(registration.anchor_px) != Vector2(144, 280): return "registration_anchor"
	if not _number(registration.get("anatomical_ground_y")) or registration.anatomical_ground_y != 278: return "registration_anatomical_ground"
	if not _number(registration.get("source_scale")) or absf(float(registration.source_scale) - .085) > 0.000000001: return "registration_source_scale"
	if not _vector(registration.get("torso_pivot_source")) or _v(registration.torso_pivot_source) != Vector2(210, 1175): return "registration_torso_pivot"
	if not _vector(registration.get("head_pivot_source")) or _v(registration.head_pivot_source) != Vector2(866, 610): return "registration_head_pivot"
	if not registration.get("layer_order") is Array or registration.layer_order != ORDER: return "registration_layer_order"
	if not registration.get("parts") is Dictionary: return "registration_parts_missing"
	if registration.parts.size() != ORDER.size(): return "registration_parts_count"
	if not registration.get("quality_holds") is Dictionary: return "registration_quality_holds_missing"
	if not registration.quality_holds.get("face_source_corner_reach") is Dictionary or not registration.quality_holds.face_source_corner_reach.get("status") is String or registration.quality_holds.face_source_corner_reach.status != "HOLD": return "registration_inherited_hold_missing"
	for name in ORDER:
		if not registration.parts.get(name) is Dictionary: return "part_missing:" + name
		var part: Dictionary = registration.parts[name]
		for key in ["source_offset", "packed_size", "original_size", "pivot_source", "pivot_packed", "trim_origin", "trim_size"]:
			if not _vector(part.get(key)): return "part_vector:" + name + ":" + key
		if _v(part.packed_size).x <= 2 or _v(part.packed_size).y <= 2: return "part_texture_size:" + name
		if not _number(part.get("padding")) or part.padding != 1: return "part_padding:" + name
		if _v(part.source_offset) != _v(part.trim_origin) - Vector2.ONE: return "part_source_offset:" + name
		if _v(part.pivot_packed) != _v(part.pivot_source) - _v(part.source_offset): return "part_pivot_offset:" + name
		if _v(part.packed_size) != _v(part.trim_size) + Vector2.ONE * 2: return "part_trim_size:" + name
		if not part.get("alpha_support_hull") is Array or part.alpha_support_hull.is_empty(): return "part_alpha_support:" + name
		for point in part.alpha_support_hull:
			if not point is Dictionary or not _vector(point.get("point")) or not _vector(point.get("pixel")) or not _number(point.get("alpha")): return "part_alpha_witness:" + name
			if float(point.alpha) < 1 or float(point.alpha) > 255: return "part_alpha_range:" + name
		if name.ends_with("_foot"):
			if not _number(part.get("scale")) or float(part.scale) <= 0: return "part_foot_scale:" + name
			if absf(float(part.scale) - float(LIMB_GEOMETRY[name].scale)) > 0.000000001: return "part_fixed_foot_scale:" + name
		elif name.begins_with("left_") or name.begins_with("right_"):
			if not _vector(part.get("native_axis")) or _v(part.native_axis).length() <= 0: return "part_native_axis:" + name
			for key in ["native_length", "target_bone_length", "fixed_width_scale"]:
				if not _number(part.get(key)) or float(part[key]) <= 0: return "part_scale:" + name + ":" + key
			if _v(part.native_axis) != _v(LIMB_GEOMETRY[name].axis) or absf(float(part.native_length) - float(LIMB_GEOMETRY[name].length)) > 0.000000001: return "part_fixed_native_geometry:" + name
			var target = 60.5 if name.ends_with("_thigh") or name.ends_with("_shin") else (39.0 if name.ends_with("_upper_arm") else 35.0)
			if absf(float(part.target_bone_length) - target) > 0.0000001: return "part_fixed_bone:" + name
			var width = target / float(LIMB_GEOMETRY[name].length)
			if absf(float(part.fixed_width_scale) - width) > 0.0000001: return "part_fixed_width:" + name
			if part.has("width_scale") and (not _number(part.width_scale) or absf(float(part.width_scale) - width) > 0.0000001): return "part_original_width:" + name
		if LIMB_GEOMETRY.has(name) and _v(part.pivot_source) != _v(LIMB_GEOMETRY[name].pivot): return "part_fixed_pivot:" + name
	if not registration.get("meshes") is Dictionary or not registration.meshes.get("neck") is Dictionary: return "neck_mesh_missing"
	var mesh: Dictionary = registration.meshes.neck
	if not mesh.get("points") is Array or mesh.points.size() < 3 or not mesh.get("triangles") is Array or mesh.triangles.is_empty(): return "neck_mesh_topology"
	for point in mesh.points:
		if not _vector(point): return "neck_mesh_source_point"
	for triangle in mesh.triangles:
		if not triangle is Array or triangle.size() != 3: return "neck_mesh_triangle"
		for index in triangle:
			if not _number(index) or float(index) != floor(float(index)) or int(index) < 0 or int(index) >= mesh.points.size(): return "neck_mesh_index"
		if absf(_area(mesh.points, triangle)) <= .000001: return "neck_mesh_source_degenerate"
	return ""

func _validate_row(row: Dictionary, registration: Dictionary) -> String:
	if not row.get("id") is String or not row.get("sequence_phase") is String: return "row_identity"
	if not _number(row.get("core_tick")) or float(row.core_tick) != floor(float(row.core_tick)) or float(row.core_tick) < 0 or float(row.core_tick) > MAX_COUNTER: return "row_tick"
	if not _number(row.get("source_scale")) or absf(float(row.source_scale) - float(registration.source_scale)) > 0.000000001: return "row_stale_source_scale"
	if not _vector(row.get("source_hip")) or _v(row.source_hip) != _v(registration.torso_pivot_source): return "row_source_pivot"
	if not _number(row.get("head_relative_angle")) or not _vector(row.get("head_control_source")) or not _vector(row.get("near_plate_offset_source")): return "row_local_controls"
	if not row.get("pose") is Dictionary: return "row_pose_missing"
	var pose: Dictionary = row.pose
	if not _vector(pose.get("pelvis")) or not _vector(pose.get("torso")) or not _number(pose.get("torso_angle")): return "row_torso_pose"
	for side in ["left", "right"]:
		for limb in ["leg", "arm"]:
			var key = side + "_" + limb
			if not pose.get(key) is Dictionary: return "row_limb_missing:" + key
			var joints = ["hip", "knee", "ankle"] if limb == "leg" else ["shoulder", "elbow", "wrist"]
			for joint in joints:
				if not _vector(pose[key].get(joint)): return "row_joint:" + key + ":" + joint
			if pose[key].get("clamped", false): return "row_clamped:" + key
			if limb == "leg" and not _number(pose[key].get("foot_angle")): return "row_foot_angle:" + side
			if limb == "leg" and not pose[key].get("contact") is bool: return "row_support_status:" + side
			var lengths = [60.5, 60.5] if limb == "leg" else [39.0, 35.0]
			for i in range(2):
				if absf(_v(pose[key][joints[i]]).distance_to(_v(pose[key][joints[i+1]])) - lengths[i]) > BONE_EPSILON: return "row_fixed_bone_length:" + key + ":" + joints[i]
	if not row.get("mesh") is Dictionary or not row.mesh.get("neck") is Dictionary: return "row_neck_mesh_missing"
	var neck: Dictionary = row.mesh.neck
	var mesh: Dictionary = registration.meshes.neck
	if not neck.get("folded_triangles") is Array or not neck.folded_triangles.is_empty(): return "row_reported_mesh_fold"
	if not neck.get("destinations") is Array or neck.destinations.size() != mesh.points.size(): return "row_neck_vertex_count"
	for point in neck.destinations:
		if not _vector(point): return "row_neck_destination"
	for triangle in mesh.triangles:
		var source_area = _area(mesh.points, triangle)
		var destination_area = _area(neck.destinations, triangle)
		if absf(destination_area) <= .000001 or source_area * destination_area <= 0: return "row_geometric_mesh_fold"
	return ""

func _limb_transform(name: String, part: Dictionary, pose: Dictionary) -> Transform2D:
	var side = "right" if name.begins_with("right_") else "left"
	if name.ends_with("_foot"):
		var leg: Dictionary = pose[side + "_leg"]
		var transform = Transform2D(float(leg.foot_angle), Vector2.ZERO).scaled(Vector2.ONE * float(part.scale))
		transform.origin = _v(leg.ankle) - transform.basis_xform(_v(part.pivot_source))
		return transform
	var joint: Vector2
	var next_joint: Vector2
	if name.ends_with("_thigh"):
		joint = _v(pose[side + "_leg"].hip); next_joint = _v(pose[side + "_leg"].knee)
	elif name.ends_with("_shin"):
		joint = _v(pose[side + "_leg"].knee); next_joint = _v(pose[side + "_leg"].ankle)
	elif name.ends_with("_upper_arm"):
		joint = _v(pose[side + "_arm"].shoulder); next_joint = _v(pose[side + "_arm"].elbow)
	else:
		joint = _v(pose[side + "_arm"].elbow); next_joint = _v(pose[side + "_arm"].wrist)
	var native_direction = _v(part.native_axis).normalized()
	var native_across = Vector2(native_direction.y, -native_direction.x)
	var target_direction = (next_joint - joint).normalized()
	var target_across = Vector2(target_direction.y, -target_direction.x)
	var length_scale = joint.distance_to(next_joint) / float(part.native_length)
	var across_scale = float(part.fixed_width_scale)
	var x = target_across * native_across.x * across_scale + target_direction * native_direction.x * length_scale
	var y = target_across * native_across.y * across_scale + target_direction * native_direction.y * length_scale
	var transform = Transform2D(x, y, Vector2.ZERO)
	transform.origin = joint - transform.basis_xform(_v(part.pivot_source))
	return transform

func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _vector(value) -> bool:
	if value is Vector2: return value.is_finite()
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and _v(value).is_finite()

func _v(value) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))

func _area(points: Array, triangle: Array) -> float:
	return (_v(points[int(triangle[1])]) - _v(points[int(triangle[0])])).cross(_v(points[int(triangle[2])]) - _v(points[int(triangle[0])]))

func _bounds(points: PackedVector2Array) -> Rect2:
	var result = Rect2(points[0], Vector2.ZERO)
	for point in points: result = result.expand(point)
	return result

func _inside_canvas(point: Vector2) -> bool:
	return point.x >= 0 and point.x <= 288 and point.y >= 0 and point.y <= 288
