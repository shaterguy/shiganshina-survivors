extends RefCounted
const F = preload("res://tests/corridor_mobility_presentation/presentation_fixture.gd")
const Main = preload("res://tests/terrain_mobility_view/test_authoritative_roof_view.gd")
class Capture:
	extends "res://game/presentation/world_view.gd"
	var emitted: Array = []
	func _world_transform(_point: Vector2,_rotation := 0.0,_scale := Vector2.ONE) -> void: pass
	func _world_rect(texture: Texture2D,rect: Rect2,_tiled: bool,color := Color.WHITE) -> void:
		emitted.append({"kind":"mobility" if texture == _mobility_textures.get("wire") else "rect","rect":rect,"color":color})
	func _world_region(_texture: Texture2D,_rect: Rect2,_region: Rect2,color := Color.WHITE) -> void:
		emitted.append({"kind":"region","color":color})
	func _draw_city_ground(_command: Dictionary) -> void: pass
	func capture() -> Array:
		emitted.clear(); _draw(); return emitted.duplicate(true)
func run(t) -> void:
	var view = Capture.new()
	view.load_manifest(); view._viewport_size = Vector2(800,450)
	if not F.available(t): view.free(); return
	for phase in ["ground","boost"]:
		var s: Dictionary = F.make(t)
		if s.is_empty(): continue
		t.check(phase == "ground" or F.reach(s,phase),"travel feedback fixture reaches actual Core "+phase)
		if s.state.player_mobility.phase != phase: continue
		var snapshot: Dictionary = s.core.snapshot(s.state)
		var frozen: PackedByteArray = var_to_bytes(snapshot)
		view.present_city(snapshot,Main.new()._terrain(s.core,s.state))
		var commands: Dictionary = view.mobility_commands()
		t.check(commands.landing_position == null,"corridor never exposes an airborne landing marker in "+phase)
		var raster: Array = view.capture()
		var cyan: Array = raster.filter(func(c): return c.kind == "mobility" and c.color.g > c.color.r*2.0 and c.color.b > c.color.r*2.0)
		if phase == "ground":
			t.check(commands.travel.is_empty() and cyan.is_empty(),"ordinary ground motion has no corridor boost raster")
		else:
			t.check(cyan.size() == 3,"actual corridor draw emits three cyan directional streaks")
			view.reduce_effects = true
			t.check(view.mobility_commands() == commands,"reduced effects preserves exact corridor projection")
			var reduced: Array = view.capture().filter(func(c): return c.kind == "mobility" and c.color.g > c.color.r*2.0 and c.color.b > c.color.r*2.0)
			t.check(reduced.size() == 1 and reduced[0] == cyan[0],"reduced effects retains essential cyan direction cue without extra streaks")
			view.reduce_effects = false
			_projection_boundaries(t,view,s,snapshot,commands)
		t.check(var_to_bytes(snapshot) == frozen,"travel presentation leaves actual Core snapshot unchanged in "+phase)
	t.check(not view._mobility_textures.has("landing"),"corridor never creates the obsolete landing-ring raster")
	_danger_colors(t,view)
	view.free()
func _projection_boundaries(t,view,s: Dictionary,snapshot: Dictionary,command: Dictionary) -> void:
	var shifted: Dictionary = snapshot.duplicate(true)
	shifted.world.origin_chunk = ["-1","0"]; shifted.player.position[0] += 768.0
	view.present(shifted)
	var after: Dictionary = view.mobility_commands()
	t.check(after.wires.size() == 2 and after.travel.position-view._camera == command.travel.position-F.vec(snapshot.player.position),"travel cue stays screen invariant under one origin translation")
	var huge: Dictionary = snapshot.duplicate(true)
	huge.world.origin_chunk = ["9007199254740993","-9007199254740994"]
	for path_point in huge.player_mobility.path: path_point.chunk = _translate(path_point.chunk,huge.world.origin_chunk)
	for anchor in huge.player_mobility.anchors: anchor.chunk = _translate(anchor.chunk,huge.world.origin_chunk)
	huge.player_mobility.landing.chunk = _translate(huge.player_mobility.landing.chunk,huge.world.origin_chunk)
	view.present(huge)
	t.check(view.mobility_commands().wires == command.wires,"large canonical chunk addresses preserve paired attachment coordinates")
	var ended := snapshot.duplicate(true)
	ended.player_mobility.phase = "ground"
	view.present(ended)
	t.check(view.mobility_commands().wires.is_empty() and view.mobility_commands().travel.is_empty(),"ground authority removes every corridor attachment and travel cue")
	var hazard: Dictionary = F.F.hazard("corridor-danger-overlap","circle",{"origin":snapshot.player.position.duplicate(),"radius":36.0,"warning_ticks":10,"active_ticks":5,"damage":1.0})
	hazard.origin_revision = s.state.world.origin_revision
	F.step(s,Vector2.UP,[hazard])
	view.present_city(s.core.snapshot(s.state),Main.new()._terrain(s.core,s.state)); view.reduce_effects = true
	var emitted: Array = view.capture()
	t.check(not s.state.telegraphs.is_empty() and emitted.any(func(c):return c.kind == "mobility") and emitted.back().kind == "region" and emitted.back().color.r > emitted.back().color.g*2.0,"red danger remains above simultaneous cyan corridor feedback under reduced effects")
	view.reduce_effects = false
func _translate(chunk: Array,origin: Array) -> Array:
	return [str(chunk[0].to_int()+origin[0].to_int()),str(chunk[1].to_int()+origin[1].to_int())]
func _danger_colors(t,view) -> void:
	view._snapshot = {"active_tick":10}
	for shape in ["circle","line","sector"]:
		for active in [false,true]:
			for reduced in [false,true]:
				view.reduce_effects = reduced; view.emitted.clear()
				var hazard: Dictionary = {"shape":shape,"origin":[0.0,0.0],"direction":[1.0,0.0],"radius":36.0,"width":20.0,"length":80.0,"arc_degrees":150.0,"active_from_tick":10 if active else 11}
				var before: PackedByteArray = var_to_bytes(hazard)
				view._draw_telegraph(hazard)
				t.check(not view.emitted.is_empty() and view.emitted.all(func(c): return c.color.r > c.color.g*2.0 and c.color.r > c.color.b*2.0 and c.color.a >= 0.50),"enemy warning is red and remains visible: %s active=%s reduced=%s" % [shape,active,reduced])
				t.check(var_to_bytes(hazard) == before,"red danger tint leaves exact authoritative hazard geometry unchanged")
