extends RefCounted
const PATH = "res://game/presentation/armored/armored_raster.gd"
const COMPILER = preload("res://game/presentation/armored/armored_pose_packet.gd")

func run(t) -> void:
	t.check(FileAccess.file_exists(PATH), "persistent one-actor raster owner exists")
	if not FileAccess.file_exists(PATH): return
	var script = load(PATH)
	t.check(script != null and script.can_instantiate(), "raster owner loads")
	if script == null or not script.can_instantiate(): return
	var registration = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/rig/armored_runtime_v1/registration.json"))
	var rows = JSON.parse_string(FileAccess.get_file_as_string("res://tests/armored_raster/golden_rows.json")).rows
	var owner = script.new()
	t.root.add_child(owner)
	var result = owner.configure(registration)
	t.check(result.ok, "exact runtime sources configure atomically")
	if not result.ok: owner.free(); return
	var viewport: SubViewport = owner.get_child(0)
	t.check(owner.get_child_count() == 1 and viewport.size == Vector2i(288, 288), "one fixed native target")
	t.check(viewport.world_2d != t.root.world_2d, "own isolated World2D")
	t.check(viewport.transparent_bg and viewport.render_target_clear_mode == SubViewport.CLEAR_MODE_ALWAYS, "transparent clear on every update")
	t.check(viewport.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST and viewport.canvas_item_default_texture_repeat == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_REPEAT_DISABLED, "nearest and edge-clamp sampler")
	t.check(viewport.disable_3d and viewport.gui_disable_input and not viewport.physics_object_picking and not viewport.audio_listener_enable_2d and not viewport.audio_listener_enable_3d, "no 3D/input/physics picking/audio")
	t.check(viewport.msaa_2d == Viewport.MSAA_DISABLED and viewport.msaa_3d == Viewport.MSAA_DISABLED and not viewport.use_taa and viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and not viewport.use_hdr_2d, "no AA or HDR target")
	t.check(owner.get_raster_texture() != null and owner.get_raster_texture().get_size() == Vector2(288, 288), "persistent native texture available")
	var compiler = COMPILER.new()
	var packet: Dictionary = compiler.compile_pose(rows[0].row, registration)
	t.check(owner.present_packet(packet), "complete golden packet accepted")
	var stable = owner.debug_stats()
	for i in range(20): t.check(owner.present_packet(packet.duplicate(true)), "equal deep copy is duplicate")
	t.check(owner.debug_stats().update_requests == stable.update_requests and owner.debug_stats().generation == stable.generation, "duplicates neither redraw nor advance generation")
	packet.pose_tick += 1
	t.check(owner.present_packet(packet), "same input object with changed metadata is recognized")
	t.check(owner.debug_stats().generation == stable.generation + 1 and owner.debug_stats().update_requests == stable.update_requests, "tick-only change preserves native draw while updating packet identity")
	packet.commands[0].transform.origin.x += 1
	packet.commands[0].source_transform.origin.x += 1
	packet.commands[0].bounds.position.x += 1
	packet.bounds = packet.commands[0].bounds
	for c in packet.commands: packet.bounds = packet.bounds.merge(c.bounds)
	t.check(owner.present_packet(packet), "same input object changed draw data commits")
	t.check(owner.debug_stats().update_requests == stable.update_requests + 1, "changed draw data requests exactly one update")
	t.check(owner.debug_stats().mesh_updates == stable.mesh_updates, "affine-only changes retain unchanged neck vertex buffer")
	var accepted = owner.packet_status()
	for mutation in ["partial", "nonfinite", "fold", "uv", "size", "bounds", "clipped", "tick"]:
		var bad: Dictionary = packet.duplicate(true)
		match mutation:
			"partial": bad.commands.pop_back()
			"nonfinite": bad.commands[0].transform.origin.x = INF
			"fold": bad.commands[10].vertices[1] = bad.commands[10].vertices[0]
			"uv": bad.commands[10].uvs[0].x += .01
			"size": bad.commands[0].texture_size.x += 1
			"bounds": bad.bounds.size.x += 1
			"clipped": bad.canvas_contained = false
			"tick": bad.pose_tick = 1e30
		t.check(not owner.present_packet(bad), "bad packet rejected atomically: " + mutation)
		t.check(owner.packet_status() == accepted, "previous whole state retained: " + mutation)
	var bad_registration = registration.duplicate(true)
	bad_registration.parts.neck.texture_path = "res://missing.png"
	t.check(not owner.configure(bad_registration).ok and owner.packet_status() == accepted, "failed reconfigure preserves entire configured actor")
	owner.set_actor_visible(false)
	var hidden = owner.debug_stats().update_requests
	for fixture in rows: t.check(owner.present_packet(compiler.compile_pose(fixture.row, registration)), "hidden consumes latest complete pose")
	t.check(owner.debug_stats().update_requests == hidden and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "offscreen poses do not request redraw")
	owner.set_actor_visible(true)
	t.check(owner.debug_stats().update_requests == hidden + 1, "returning visible requests latest pose once")
	var ids = owner.debug_stats().resource_ids
	t.check(owner.debug_stats().has("resource_rids"), "owned RID identity observations available")
	if not owner.debug_stats().has("resource_rids"): owner.free(); return
	var rids = owner.debug_stats().resource_rids
	for cycle in range(120):
		for fixture in rows: owner.present_packet(compiler.compile_pose(fixture.row, registration))
		t.check(owner.debug_stats().resource_ids == ids and owner.debug_stats().resource_rids == rids, "120 action cycles retain texture/mesh/viewport identities")
	t.check(owner.debug_stats().source_decodes == 17 and owner.debug_stats().alpha_bytes == 4591880 and owner.debug_stats().mesh_surface_creations == 1, "no source decode or mesh surface churn after configure")
	var viewport_weak = weakref(viewport)
	var world_weak = weakref(viewport.world_2d)
	var mesh_weak = weakref(owner._meshes.neck)
	viewport = null
	owner.clear_actor()
	t.check(owner.get_child_count() == 0 and owner.get_raster_texture() == null and owner.local_bounds() == Rect2(), "clear releases target and prior pose")
	t.check(viewport_weak.get_ref() == null and world_weak.get_ref() == null and mesh_weak.get_ref() == null, "owned target World2D and mesh resources freed")
	t.check(owner.debug_stats().resource_ids.is_empty() and owner.debug_stats().alpha_bytes == 0, "clear drops owned texture references and alpha planes")
	t.check(not owner.present_packet(packet), "cleared actor cannot accept until configured")
	var object_baseline = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var object_peak_after_clear = object_baseline
	for i in range(50):
		t.check(owner.configure(registration).ok and owner.present_packet(compiler.compile_pose(rows[0].row, registration)), "50 create/clear cycles can reconfigure")
		var target_weak = weakref(owner.get_child(0))
		var m_weak = weakref(owner._meshes.neck)
		owner.clear_actor()
		t.check(target_weak.get_ref() == null and m_weak.get_ref() == null and owner.get_child_count() == 0, "50 cycles return to zero owned targets/meshes")
		target_weak = null
		m_weak = null
		object_peak_after_clear = maxi(object_peak_after_clear, int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	t.check(object_peak_after_clear <= object_baseline, "headless object count plateaus after every clear")
	print("ARMORED_HEADLESS_LIFECYCLE cycles=120 create_clear=50 objects_baseline=%d objects_peak_after_clear=%d native_gpu_verified=false" % [object_baseline, object_peak_after_clear])
	owner.free()
