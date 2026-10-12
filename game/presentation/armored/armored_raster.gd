extends Node
## Bounded owner of one native target. Headless tests prove objects/math only.
## A requested generation is NOT evidence that the GPU target has that generation.
const PACKET = preload("res://game/presentation/armored/armored_pose_packet.gd")
const CANVAS = Rect2(0, 0, 288, 288)
const OUTPUT_ALPHA_MODE = "premultiplied" # Transparent target RGB; final consumer must not multiply alpha twice.
const OPAQUE_THRESHOLD = 0.1 # Existing WorldView atlas overlap convention.

class DrawSurface extends Node2D:
	var commands: Array = []
	var textures: Dictionary = {}
	var meshes: Dictionary = {}
	func _draw() -> void:
		for command in commands:
			draw_set_transform_matrix(command.transform)
			if command.vertices.is_empty():
				draw_texture(textures[command.part_id], Vector2.ZERO, command.modulate)
			else:
				draw_mesh(meshes[command.part_id], textures[command.part_id], Transform2D.IDENTITY, command.modulate)
		draw_set_transform_matrix(Transform2D.IDENTITY)

var last_error = ""
var _registration: Dictionary = {}
var _textures: Dictionary = {}
var _alpha: Dictionary = {}
var _meshes: Dictionary = {}
var _packet: Dictionary = {}
var _query_commands: Array = []
var _viewport: SubViewport
var _surface: DrawSurface
var _actor_visible = true
var _dirty = false
var _generation = 0
var _update_requests = 0
var _source_decodes = 0
var _mesh_surface_creations = 0
var _mesh_updates = 0

func configure(registration: Dictionary) -> Dictionary:
	var error = PACKET.new()._validate_registration(registration)
	if not error.is_empty(): return _configure_error(error)
	var textures = {}
	var planes = {}
	var rgba_bytes = 0
	for name in PACKET.ORDER:
		var part: Dictionary = registration.parts[name]
		var path = part.get("texture_path", "")
		if not path is String or not path.begins_with("res://") or not path.ends_with(".png") or ".." in path or not ResourceLoader.exists(path, "Texture2D"): return _configure_error("source_path:" + name)
		# Raw source identity is checked when present (development). Normal
		# exported resources use Godot's .import remap; raw PNG is not required.
		if FileAccess.file_exists(path) and FileAccess.get_sha256(path) != part.get("packed_png_sha256", ""): return _configure_error("source_digest:" + name)
		var texture = load(path)
		if not texture is CompressedTexture2D: return _configure_error("source_texture:" + name)
		# Exactly one SOURCE texture decode at configure, never ViewportTexture
		# readback. Preserve exact alpha in an LA8 query buffer. Draw texture
		# and its returned Image must remain RGBA and must never be converted.
		var image: Image = texture.get_image()
		if image == null or image.get_format() != Image.FORMAT_RGBA8 or image.has_mipmaps(): return _configure_error("source_rgba:" + name)
		var size = Vector2i(image.get_size())
		if Vector2(size) != _v(part.packed_size): return _configure_error("source_size:" + name)
		var rgba = image.get_data()
		# Only border texels need the zero-RGBA check, not every source pixel.
		for x in range(size.x):
			if rgba.decode_u32(x * 4) != 0 or rgba.decode_u32(((size.y - 1) * size.x + x) * 4) != 0: return _configure_error("source_clear_border:" + name)
		for y in range(1, size.y - 1):
			if rgba.decode_u32(y * size.x * 4) != 0 or rgba.decode_u32((y * size.x + size.x - 1) * 4) != 0: return _configure_error("source_clear_border:" + name)
		# Godot's byte-format C++ conversion copies alpha without quantization.
		# A separate Image is essential: get_image() may return a shared Image.
		var alpha_image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, rgba)
		alpha_image.convert(Image.FORMAT_LA8)
		var plane = alpha_image.get_data()
		if texture.get_size() != Vector2(size): return _configure_error("source_texture:" + name)
		textures[name] = texture
		planes[name] = {"size": size, "data": plane}
		rgba_bytes += rgba.size()
	if rgba_bytes > 10 * 1024 * 1024: return _configure_error("source_base_rgba_budget")
	var neck: Dictionary = registration.meshes.neck
	if neck.points.size() > 4096 or neck.triangles.size() > 8192: return _configure_error("mesh_budget")
	# All validation/loading completed before changing the existing actor.
	clear_actor()
	_registration = registration.duplicate(true)
	_textures = textures
	_alpha = planes
	_source_decodes = PACKET.ORDER.size()
	_viewport = SubViewport.new()
	_viewport.name = "ArmoredNativeTarget"
	_viewport.size = Vector2i(288, 288)
	_viewport.world_2d = World2D.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.handle_input_locally = false
	_viewport.physics_object_picking = false
	_viewport.audio_listener_enable_2d = false
	_viewport.audio_listener_enable_3d = false
	_viewport.msaa_2d = Viewport.MSAA_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.use_taa = false
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_hdr_2d = false
	_viewport.snap_2d_transforms_to_pixel = false
	_viewport.snap_2d_vertices_to_pixel = false
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.canvas_item_default_texture_repeat = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_REPEAT_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_surface = DrawSurface.new()
	_surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_surface.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_surface.set_process_input(false)
	_surface.set_process_unhandled_input(false)
	_viewport.add_child(_surface)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices = PackedVector2Array()
	var uvs = PackedVector2Array()
	for point in neck.points:
		vertices.append(_v(point))
		uvs.append((_v(point) - _v(registration.parts.neck.source_offset)) / _v(registration.parts.neck.packed_size))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _indices(neck.triangles)
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	_meshes.neck = mesh
	_mesh_surface_creations = 1
	_surface.textures = _textures
	_surface.meshes = _meshes
	last_error = ""
	return {"ok": true, "reason": "", "base_rgba_bytes": rgba_bytes, "cached_alpha_bytes": rgba_bytes / 2, "native_gpu_verified": false}

func _configure_error(reason: String) -> Dictionary:
	last_error = reason
	return {"ok": false, "reason": reason, "native_gpu_verified": false}

func present_packet(packet: Dictionary) -> bool:
	last_error = _validate_packet(packet)
	if not last_error.is_empty(): return false
	if _packet == packet: return true
	var draw_changed = _packet.is_empty() or _packet.commands != packet.commands
	var mesh_changed = _packet.is_empty() or _packet.commands[10].vertices != packet.commands[10].vertices
	# Copy the COMPLETE packet before touching buffers; callers retain no aliases.
	_packet = packet.duplicate(true)
	_generation += 1
	if draw_changed:
		var command: Dictionary = _packet.commands[10]
		var mesh: ArrayMesh = _meshes.neck
		if mesh_changed:
			mesh.surface_update_vertex_region(0, 0, command.vertices.to_byte_array())
			var box = _bounds(command.vertices)
			mesh.custom_aabb = AABB(Vector3(box.position.x, box.position.y, -1), Vector3(box.size.x, box.size.y, 2))
			_mesh_updates += 1
		_surface.commands = _packet.commands
		_query_commands = []
		for c in _packet.commands:
			_query_commands.append({"inverse": c.transform.affine_inverse(), "bounds": c.bounds, "vertices": c.vertices, "uvs": c.uvs, "indices": c.indices, "alpha": _alpha[c.part_id], "modulate_alpha": c.modulate.a})
		_dirty = true
		_request_update()
	return true

func _validate_packet(packet: Dictionary) -> String:
	if _viewport == null: return "not_configured"
	if not packet.get("ok") is bool: return "packet_ok_type"
	if not packet.ok: return "packet_rejected"
	if not packet.get("pose_tick") is int or packet.pose_tick < 0 or packet.pose_tick > PACKET.MAX_COUNTER: return "packet_tick"
	if not packet.get("pose_id") is String or not packet.get("source_state") is String or not packet.get("support_status") is Dictionary: return "packet_identity"
	if not packet.get("canvas") is Vector2 or not packet.get("anchor_px") is Vector2 or not packet.get("anatomical_ground_y") is int: return "packet_registration_type"
	if packet.canvas != Vector2(288, 288) or packet.anchor_px != Vector2(144, 280) or packet.anatomical_ground_y != 278: return "packet_registration"
	if not packet.get("canvas_contained") is bool or not packet.get("outside_canvas") is Array: return "packet_canvas_status_type"
	if not packet.canvas_contained or not packet.outside_canvas.is_empty(): return "packet_outside_canvas"
	if not packet.get("commands") is Array or packet.commands.size() != PACKET.ORDER.size(): return "packet_incomplete"
	var combined = Rect2()
	for layer in range(PACKET.ORDER.size()):
		var c = packet.commands[layer]
		var name: String = PACKET.ORDER[layer]
		if not c is Dictionary: return "command_type"
		if not c.get("part_id") is String or not c.get("layer") is int: return "command_order_type"
		if c.part_id != name or c.layer != layer: return "command_order"
		var part: Dictionary = _registration.parts[name]
		if not c.get("transform") is Transform2D or not c.transform.is_finite() or absf(c.transform.determinant()) < .0000001: return "command_transform:" + name
		if not c.get("source_transform") is Transform2D or not c.source_transform.is_finite(): return "command_source_transform:" + name
		if not c.get("source_offset") is Vector2 or not c.get("texture_size") is Vector2 or not c.get("source_size") is Vector2: return "command_source_metadata_type:" + name
		if c.source_offset != _v(part.source_offset) or c.texture_size != _v(part.packed_size) or c.source_size != _v(part.original_size): return "command_source_metadata:" + name
		if not c.get("modulate") is Color or not _color_valid(c.modulate): return "command_modulate:" + name
		if not c.get("vertices") is PackedVector2Array or not c.get("uvs") is PackedVector2Array or not c.get("indices") is PackedInt32Array: return "command_arrays:" + name
		var support = PackedVector2Array()
		if name == "neck":
			var source: Dictionary = _registration.meshes.neck
			if c.vertices.size() != source.points.size() or c.uvs.size() != source.points.size() or c.indices != _indices(source.triangles): return "command_mesh_topology"
			if not c.transform.is_equal_approx(c.source_transform): return "command_mesh_transform"
			for i in range(c.vertices.size()):
				var uv = (_v(source.points[i]) - _v(part.source_offset)) / _v(part.packed_size)
				if not c.vertices[i].is_finite() or not c.uvs[i].is_finite() or c.uvs[i] != uv: return "command_mesh_uv"
				var world = c.transform * c.vertices[i]
				if not world.is_finite(): return "command_mesh_world"
				support.append(world)
			for triangle in source.triangles:
				if _area(c.vertices, triangle) * _area(source.points, triangle) <= .000001: return "command_mesh_fold"
		else:
			if not c.vertices.is_empty() or not c.uvs.is_empty() or not c.indices.is_empty(): return "command_unreviewed_mesh"
			if not c.transform.is_equal_approx(c.source_transform * Transform2D(0, _v(part.source_offset))): return "command_packed_transform"
			for witness in part.alpha_support_hull:
				var world = c.source_transform * _v(witness.point)
				if not world.is_finite(): return "command_alpha_world"
				support.append(world)
		var actual = _bounds(support)
		if not c.get("bounds") is Rect2 or not _rect_finite(c.bounds) or not c.bounds.is_equal_approx(actual): return "command_bounds:" + name
		if not CANVAS.encloses(actual): return "command_outside_canvas:" + name
		combined = actual if layer == 0 else combined.merge(actual)
	if not packet.get("bounds") is Rect2 or not _rect_finite(packet.bounds) or not packet.bounds.is_equal_approx(combined): return "packet_bounds"
	return ""

func alpha_local(point: Vector2) -> float:
	return _query_alpha(point, false)

func is_opaque_local(point: Vector2) -> bool:
	return _query_alpha(point, true) > OPAQUE_THRESHOLD

func _query_alpha(point: Vector2, stop_at_threshold: bool) -> float:
	if _packet.is_empty() or not point.is_finite() or not CANVAS.has_point(point): return 0.0
	# The final target is sampled on its native grid, never at the continuous
	# inverse-transformed display coordinate. Mirror/root/scale inversion is
	# the caller's responsibility, before this quantization.
	var sample = point.floor() + Vector2(.5, .5)
	if not local_bounds().has_point(sample): return 0.0
	var alpha = 0.0
	for command in _query_commands:
		if command.modulate_alpha <= 0 or not command.bounds.has_point(sample): continue
		var local: Vector2 = command.inverse * sample
		var data: Dictionary = command.alpha
		var size: Vector2i = data.size
		var texel = local
		if not command.vertices.is_empty():
			var lookup = _mesh_uv(command, local)
			if not lookup.covered: continue
			# repeat-off means clamp-to-edge, not transparent discard. The
			# verified zero border makes all out-of-range mesh UVs transparent.
			texel = lookup.uv * Vector2(size)
		else:
			if not Rect2(Vector2.ZERO, Vector2(size)).has_point(local): continue
		var x = clampi(int(floor(texel.x)), 0, size.x - 1)
		var y = clampi(int(floor(texel.y)), 0, size.y - 1)
		var source = float(data.data[(y * size.x + x) * 2 + 1]) / 255.0 * command.modulate_alpha
		alpha = source + alpha * (1.0 - source)
		# With validated nonnegative modulation/source-over, later layers
		# cannot remove coverage. This exit has the same >0.1 decision.
		if stop_at_threshold and alpha > OPAQUE_THRESHOLD: return alpha
	return alpha

func _mesh_uv(command: Dictionary, point: Vector2) -> Dictionary:
	for i in range(0, command.indices.size(), 3):
		var ia: int = command.indices[i]
		var ib: int = command.indices[i + 1]
		var ic: int = command.indices[i + 2]
		var a: Vector2 = command.vertices[ia]
		var b: Vector2 = command.vertices[ib]
		var c: Vector2 = command.vertices[ic]
		var area = (b - a).cross(c - a)
		var sign_area = 1.0 if area > 0 else -1.0
		if not _edge_covered(a, b, point, sign_area) or not _edge_covered(b, c, point, sign_area) or not _edge_covered(c, a, point, sign_area): continue
		var wa = (b - point).cross(c - point) / area
		var wb = (c - point).cross(a - point) / area
		var wc = 1.0 - wa - wb
		return {"covered": true, "uv": command.uvs[ia] * wa + command.uvs[ib] * wb + command.uvs[ic] * wc}
	return {"covered": false}

func _edge_covered(a: Vector2, b: Vector2, point: Vector2, orientation: float) -> bool:
	var edge = (b - a) * orientation
	var value = (b - a).cross(point - a) * orientation
	if value != 0.0: return value > 0.0
	# Half-open top/left edge convention: adjacent triangles do not blend
	# twice at an exact shared edge. Actual backend precision is native QA.
	return edge.y < 0.0 or (edge.y == 0.0 and edge.x > 0.0)

func set_actor_visible(value: bool) -> void:
	if value == _actor_visible: return
	_actor_visible = value
	if _viewport == null: return
	if not value:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if not _packet.is_empty(): _dirty = true
	else: _request_update()

func _request_update() -> void:
	if _actor_visible and _dirty and _viewport != null:
		_surface.queue_redraw()
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_update_requests += 1
		_dirty = false

func get_raster_texture() -> Texture2D:
	return _viewport.get_texture() if _viewport != null else null

func local_bounds() -> Rect2:
	return _packet.get("bounds", Rect2())

func packet_status() -> Dictionary:
	if _packet.is_empty(): return {}
	return {"generation": _generation, "pose_tick": _packet.pose_tick, "pose_id": _packet.pose_id, "source_state": _packet.source_state, "bounds": _packet.bounds, "support_status": _packet.support_status.duplicate(true), "output_alpha_mode": OUTPUT_ALPHA_MODE, "native_gpu_verified": false}

func debug_stats() -> Dictionary:
	var ids: Array = []
	var rids: Array = []
	var alpha_bytes = 0
	for name in PACKET.ORDER:
		if _textures.has(name):
			ids.append(_textures[name].get_instance_id())
			rids.append(_textures[name].get_rid())
		if _alpha.has(name): alpha_bytes += _alpha[name].data.size()
	if _viewport != null:
		ids.append(_viewport.get_instance_id())
		ids.append(_viewport.world_2d.get_instance_id())
		ids.append(_surface.get_instance_id())
		rids.append(_viewport.get_viewport_rid())
		rids.append(_viewport.world_2d.canvas)
		rids.append(_surface.get_canvas_item())
	for mesh in _meshes.values():
		ids.append(mesh.get_instance_id())
		rids.append(mesh.get_rid())
	return {"resource_ids": ids, "resource_rids": rids, "alpha_bytes": alpha_bytes, "source_decodes": _source_decodes, "mesh_surface_creations": _mesh_surface_creations, "mesh_updates": _mesh_updates, "generation": _generation, "update_requests": _update_requests}

func clear_actor() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_surface.commands = []
		_surface.textures = {}
		_surface.meshes = {}
		remove_child(_viewport)
		_viewport.free()
	_viewport = null
	_surface = null
	_textures.clear()
	_alpha.clear()
	_meshes.clear()
	_registration.clear()
	_packet.clear()
	_query_commands.clear()
	_dirty = false
	_generation = 0
	_update_requests = 0
	_source_decodes = 0
	_mesh_surface_creations = 0
	_mesh_updates = 0
	last_error = ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: clear_actor()

func _v(value) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))
func _indices(triangles: Array) -> PackedInt32Array:
	var result = PackedInt32Array()
	for triangle in triangles:
		for i in triangle: result.append(int(i))
	return result
func _area(points, triangle) -> float:
	return (_v(points[triangle[1]]) - _v(points[triangle[0]])).cross(_v(points[triangle[2]]) - _v(points[triangle[0]]))
func _bounds(points: PackedVector2Array) -> Rect2:
	var lo = points[0]
	var hi = lo
	for point in points:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)
func _rect_finite(rect: Rect2) -> bool:
	return rect.position.is_finite() and rect.size.is_finite() and rect.size.x >= 0 and rect.size.y >= 0
func _color_valid(color: Color) -> bool:
	for value in [color.r, color.g, color.b, color.a]:
		if not is_finite(value) or value < 0 or value > 1: return false
	return true
