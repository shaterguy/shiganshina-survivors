extends SceneTree
## Headless math report only. This never creates a renderer or native scene.
const PACKET = preload("res://game/presentation/armored/armored_pose_packet.gd")

func plain(value):
	if value is Vector2: return [value.x, value.y]
	if value is Rect2: return [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is Transform2D: return [value.x.x, value.x.y, value.y.x, value.y.y, value.origin.x, value.origin.y]
	if value is Color: return [value.r, value.g, value.b, value.a]
	if value is Dictionary:
		var result = {}
		for key in value: result[key] = plain(value[key])
		return result
	if value is Array or value is PackedVector2Array or value is PackedInt32Array:
		var result = []
		for item in value: result.append(plain(item))
		return result
	return value

func _initialize() -> void:
	var compiler = PACKET.new()
	var registration = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/rig/armored_runtime_v1/registration.json"))
	var golden = JSON.parse_string(FileAccess.get_file_as_string("res://tests/armored_raster/golden_rows.json"))
	var rows = []
	for fixture in golden.rows:
		var packet = compiler.compile_pose(fixture.row, registration)
		if not packet.ok:
			push_error(packet.reason); quit(1); return
		rows.append({"fixture_id": fixture.fixture_id, "pose_tick": packet.pose_tick,
			"bounds": packet.bounds, "canvas_contained": packet.canvas_contained,
			"outside_canvas": packet.outside_canvas, "commands": packet.commands,
			"quality_status": packet.quality_status})
	var output = ProjectSettings.globalize_path("res://../evidence/task1-golden-packets.json")
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file == null: push_error("report_write_failed"); quit(1); return
	file.store_string(JSON.stringify(plain({"method": "pure headless affine/UV/alpha-support math; no native/GPU result", "rows": rows}), "\t") + "\n")
	file.close()
	print("Pure packet report: ", rows.size(), " frozen keys")
	quit(0)
