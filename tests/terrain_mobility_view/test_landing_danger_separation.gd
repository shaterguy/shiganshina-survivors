extends RefCounted
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
const Address = preload("res://game/world/world_address.gd")
class Capture:
	extends "res://game/presentation/world_view.gd"
	var emitted: Array = []
	func _world_transform(_point: Vector2,_rotation := 0.0,_scale := Vector2.ONE) -> void: pass
	func _world_rect(texture: Texture2D,rect: Rect2,_tiled: bool,color := Color.WHITE) -> void:
		emitted.append({"kind":"landing" if texture == _mobility_textures.get("landing") else "rect","rect":rect,"color":color})
	func _world_region(_texture: Texture2D,_rect: Rect2,_region: Rect2,color := Color.WHITE) -> void:
		emitted.append({"kind":"region","color":color})
	func _draw_city_ground(_command: Dictionary) -> void: pass
	func capture() -> Array:
		emitted.clear(); _draw(); return emitted.duplicate(true)
func run(t) -> void:
	var view = Capture.new()
	view.load_manifest()
	view._viewport_size = Vector2(800,450)
	if not F.available(t): view.free(); return
	for phase in ["ground","rise","over","land"]:
		var s: Dictionary = F.make(t)
		if s.is_empty(): continue
		t.check(phase == "ground" or F.reach(s,phase),"landing marker fixture reaches actual Core "+phase)
		if s.state.player_mobility.phase != phase: continue
		var snapshot: Dictionary = s.core.snapshot(s.state)
		var frozen: PackedByteArray = var_to_bytes(snapshot)
		view.present_city(snapshot,_terrain(s))
		var commands: Dictionary = view.mobility_commands()
		var point: Variant = commands.get("landing_position")
		if phase == "ground":
			t.check(point == null,"ground phase has no planned airborne landing marker")
		else:
			var landing: Dictionary = snapshot.player_mobility.landing
			var expected: Dictionary = Address.relative(landing.chunk,F.vec(landing.local),snapshot.world.origin_chunk)
			t.check(point is Vector2 and expected.get("ok",false) and point == expected.local,"landing marker uses actual accepted landing address during "+phase)
			var raster: Array = view.capture()
			var markers: Array = raster.filter(func(c): return c.kind == "landing")
			t.check(markers.size() == 2 and markers.back().color.g > markers.back().color.r*2.0 and markers.back().color.b > markers.back().color.r*2.0,"actual draw emits cyan ring and center with dark backing during "+phase)
			view.reduce_effects = true
			t.check(view.mobility_commands() == commands,"reduced effects preserves exact planned landing projection during "+phase)
			t.check(view.capture().filter(func(c): return c.kind == "landing") == markers,"reduced effects retains essential landing raster during "+phase)
			view.reduce_effects = false
			if phase == "over": _projection_boundaries(t,view,s,snapshot,point)
		t.check(var_to_bytes(snapshot) == frozen,"landing presentation leaves actual Core snapshot unchanged during "+phase)
	var texture: Texture2D = view._mobility_textures.get("landing")
	t.check(texture != null,"landing draw uses a dedicated hollow ring raster")
	if texture != null:
		var raster: Image = texture.get_image()
		t.check(raster.get_size() == Vector2i(33,33) and raster.get_pixel(16,16).a > 0.9 and raster.get_pixel(16,7).a == 0.0 and raster.get_pixel(16,1).a > 0.9,"landing shape is a hollow circle plus center dot rather than a filled hazard area")
	_danger_colors(t,view)
	view.free()
func _terrain(s: Dictionary) -> Dictionary:
	var terrain: Dictionary = s.core.world_render_view(s.state)
	terrain.world_revision = s.core.world_status().get("world_revision",s.state.world.world_revision)
	return terrain
func _projection_boundaries(t,view,s: Dictionary,snapshot: Dictionary,point: Variant) -> void:
	# These copied snapshots exercise renderer address boundaries only. Actual
	# Core phases, route, landing and geometry remain the source of the fixture.
	var shifted: Dictionary = snapshot.duplicate(true)
	shifted.world.origin_chunk = ["-1","0"]
	shifted.player.position[0] += 768.0
	view.present(shifted)
	var after: Variant = view.mobility_commands().get("landing_position")
	t.check(point is Vector2 and after is Vector2 and after-view._camera == point-F.vec(snapshot.player.position),"landing stays screen invariant under one canonical origin translation")
	var huge: Dictionary = snapshot.duplicate(true)
	huge.world.origin_chunk = ["9007199254740993","-9007199254740994"]
	for path_point in huge.player_mobility.path:
		path_point.chunk = _translate(path_point.chunk,huge.world.origin_chunk)
	huge.player_mobility.anchor.chunk = _translate(huge.player_mobility.anchor.chunk,huge.world.origin_chunk)
	huge.player_mobility.anchor.pass_start.chunk = _translate(huge.player_mobility.anchor.pass_start.chunk,huge.world.origin_chunk)
	huge.player_mobility.anchor.pass_end.chunk = _translate(huge.player_mobility.anchor.pass_end.chunk,huge.world.origin_chunk)
	huge.player_mobility.landing.chunk = _translate(huge.player_mobility.landing.chunk,huge.world.origin_chunk)
	view.present(huge)
	t.check(point is Vector2 and view.mobility_commands().get("landing_position") == point,"large canonical chunk addresses preserve exact landing local position")
	for mutation in ["cancelled","empty","bad_chunk","far_chunk","bad_local","nonfinite"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		match mutation:
			"cancelled": invalid.player_mobility.cancelled = true
			"empty": invalid.player_mobility.landing = {}
			"bad_chunk": invalid.player_mobility.landing.chunk = ["01","0"]
			"far_chunk": invalid.player_mobility.landing.chunk = ["9007199254740993","0"]
			"bad_local": invalid.player_mobility.landing.local = ["invalid",0.0]
			"nonfinite": invalid.player_mobility.landing.local = [INF,0.0]
		view.present(invalid)
		t.check(view.mobility_commands().get("landing_position") == null,"cancelled or invalid landing does not emit a marker: "+mutation)
	var hazard: Dictionary = F.F.hazard("landing-danger-overlap","circle",{"origin":snapshot.player.position.duplicate(),"radius":36.0,"warning_ticks":10,"active_ticks":5,"damage":1.0})
	hazard.origin_revision = s.state.world.origin_revision
	F.step(s,Vector2.UP,[hazard])
	view.present_city(s.core.snapshot(s.state),_terrain(s))
	view.reduce_effects = true
	var emitted: Array = view.capture()
	t.check(not s.state.telegraphs.is_empty() and emitted.filter(func(c): return c.kind == "landing").size() == 2 and not emitted.is_empty() and emitted.back().kind == "region" and emitted.back().color.r > emitted.back().color.g*2.0,"red danger remains above simultaneous cyan landing marker under reduced effects")
	view.reduce_effects = false
func _translate(chunk: Array,origin: Array) -> Array:
	return [str(chunk[0].to_int()+origin[0].to_int()),str(chunk[1].to_int()+origin[1].to_int())]
func _danger_colors(t,view) -> void:
	view._snapshot = {"active_tick":10}
	for shape in ["circle","line","sector"]:
		for active in [false,true]:
			for reduced in [false,true]:
				view.reduce_effects = reduced
				view.emitted.clear()
				var hazard: Dictionary = {"shape":shape,"origin":[0.0,0.0],"direction":[1.0,0.0],"radius":36.0,"width":20.0,"length":80.0,"arc_degrees":150.0,"active_from_tick":10 if active else 11}
				var before: PackedByteArray = var_to_bytes(hazard)
				view._draw_telegraph(hazard)
				t.check(not view.emitted.is_empty() and view.emitted.all(func(c): return c.color.r > c.color.g*2.0 and c.color.r > c.color.b*2.0 and c.color.a >= 0.50),"enemy warning is red and remains visible: %s active=%s reduced=%s" % [shape,active,reduced])
				t.check(var_to_bytes(hazard) == before,"red danger tint leaves exact authoritative hazard geometry unchanged")
