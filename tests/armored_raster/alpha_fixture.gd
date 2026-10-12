extends RefCounted
const PACKET = preload("res://game/presentation/armored/armored_pose_packet.gd")
const PATH = "res://tests/armored_raster/fixtures/alpha_rgba.png"
const PIXELS = [Vector3i(1, 1, 128), Vector3i(2, 1, 64), Vector3i(1, 2, 255), Vector3i(2, 2, 1), Vector3i(3, 1, 13), Vector3i(3, 2, 26), Vector3i(4, 4, 255)]
func registration() -> Dictionary:
	var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/rig/armored_runtime_v1/registration.json"))
	for name in PACKET.ORDER:
		var p: Dictionary = result.parts[name]
		p.texture_path = PATH
		p.packed_png_sha256 = FileAccess.get_sha256(PATH)
		p.packed_size = [6, 6]
		p.source_offset = [7, 11]
		p.trim_origin = [8, 12]
		p.trim_size = [4, 4]
		p.pivot_packed = [p.pivot_source[0] - 7, p.pivot_source[1] - 11]
		p.alpha_support_hull = []
		for pixel in PIXELS:
			for corner in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
				p.alpha_support_hull.append({"point": [pixel.x + 7 + corner.x, pixel.y + 11 + corner.y], "pixel": [pixel.x + 7, pixel.y + 11], "alpha": pixel.z})
	result.meshes.neck = {"points": [[4, 8], [16, 8], [16, 20], [4, 20]], "triangles": [[0, 1, 2], [0, 2, 3]]}
	return result
func packet(reg: Dictionary) -> Dictionary:
	var commands: Array = []
	for layer in range(PACKET.ORDER.size()):
		var name: String = PACKET.ORDER[layer]
		var source = Transform2D(0, Vector2(13, 9))
		var c = {"part_id": name, "layer": layer, "transform": Transform2D(0, Vector2(20, 20)), "source_transform": source, "source_offset": Vector2(7, 11), "source_size": Vector2(reg.parts[name].original_size[0], reg.parts[name].original_size[1]), "texture_size": Vector2(6, 6), "modulate": Color(1, 1, 1, 0), "vertices": PackedVector2Array(), "uvs": PackedVector2Array(), "indices": PackedInt32Array(), "bounds": Rect2(21, 21, 4, 4)}
		if name == "neck":
			c.transform = Transform2D.IDENTITY
			c.source_transform = Transform2D.IDENTITY
			c.vertices = PackedVector2Array([Vector2(100, 100), Vector2(112, 100), Vector2(112, 112), Vector2(100, 112)])
			c.uvs = PackedVector2Array([Vector2(-.5, -.5), Vector2(1.5, -.5), Vector2(1.5, 1.5), Vector2(-.5, 1.5)])
			c.indices = PackedInt32Array([0, 1, 2, 0, 2, 3])
			c.bounds = Rect2(100, 100, 12, 12)
		commands.append(c)
	return {"ok": true, "pose_tick": 1, "pose_id": "constructed_alpha", "source_state": "test", "support_status": {}, "canvas": Vector2(288, 288), "anchor_px": Vector2(144, 280), "anatomical_ground_y": 278, "canvas_contained": true, "outside_canvas": [], "commands": commands, "bounds": Rect2(21, 21, 91, 91)}
func scalar_at(x: int, y: int) -> float:
	for p in PIXELS:
		if p.x == x and p.y == y: return p.z / 255.0
	return 0.0
