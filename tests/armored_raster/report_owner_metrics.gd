extends SceneTree
## Headless CPU/object probe only, not a rendered/native/device benchmark.
const RASTER = preload("res://game/presentation/armored/armored_raster.gd")
const COMPILER = preload("res://game/presentation/armored/armored_pose_packet.gd")
func _initialize() -> void:
	call_deferred("run")
func percentiles(values: Array) -> Dictionary:
	values.sort()
	return {"p50_us": values[int(ceil(values.size() * .5)) - 1], "p95_us": values[int(ceil(values.size() * .95)) - 1], "p99_us": values[int(ceil(values.size() * .99)) - 1], "max_us": values[-1]}
func run() -> void:
	var reg = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/rig/armored_runtime_v1/registration.json"))
	var rows = JSON.parse_string(FileAccess.get_file_as_string("res://tests/armored_raster/golden_rows.json")).rows
	var compiler = COMPILER.new()
	var packets: Array = []
	for fixture in rows: packets.append(compiler.compile_pose(fixture.row, reg))
	var owner = RASTER.new()
	root.add_child(owner)
	var baseline = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var started = Time.get_ticks_usec()
	var result: Dictionary = owner.configure(reg)
	var configure_us = Time.get_ticks_usec() - started
	if not result.ok: push_error(result.reason); owner.free(); quit(1); return
	var configured = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	owner.set_actor_visible(false)
	var submission: Array = []
	for cycle in range(10):
		for packet in packets:
			started = Time.get_ticks_usec()
			if not owner.present_packet(packet): push_error(owner.last_error); owner.free(); quit(1); return
			submission.append(Time.get_ticks_usec() - started)
	owner.present_packet(packets[0])
	var bounds: Rect2 = packets[0].bounds
	var neck_bounds: Rect2 = packets[0].commands[10].bounds
	var points = [Vector2(-1, -1), bounds.get_center(), neck_bounds.get_center(), bounds.position + Vector2.ONE, bounds.end - Vector2.ONE]
	var alpha: Array = []
	var composed: Array = []
	for i in range(1000):
		var point: Vector2 = points[i % points.size()]
		started = Time.get_ticks_usec()
		owner.is_opaque_local(point)
		alpha.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		owner.alpha_local(point)
		composed.append(Time.get_ticks_usec() - started)
	var stats: Dictionary = owner.debug_stats()
	var report = {"environment": "Godot4.6.3 headless dummy; concurrent host work; not Android", "native_gpu_verified": false, "configure_us": configure_us, "changed_packet_validate_copy_submit": percentiles(submission), "opaque_query": percentiles(alpha), "full_alpha_query": percentiles(composed), "memory_static_before": baseline, "memory_static_after_configure": configured, "memory_static_delta": configured - baseline, "base_rgba_bytes": result.base_rgba_bytes, "cached_alpha_bytes": result.cached_alpha_bytes, "owned_resource_count": stats.resource_ids.size(), "owned_rid_handles": stats.resource_rids.size(), "source_decodes": stats.source_decodes, "mesh_surface_creations": stats.mesh_surface_creations, "update_requests_offscreen": stats.update_requests, "mobile_resident_delta": "unmeasured", "target_rgba8_bytes_estimate": 331776}
	owner.free()
	var output = str(OS.get_cmdline_user_args()[0])
	var file = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print(JSON.stringify(report))
	quit(0)
