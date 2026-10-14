extends RefCounted
const City = preload("res://tests/city_presentation/test_world_view_city.gd")
class Capture extends "res://game/presentation/world_view.gd":
	var emitted: Array = []
	var mobility_reads := 0
	func mobility_commands() -> Dictionary:
		mobility_reads += 1
		return super.mobility_commands()
	func _draw_city_ground(_command: Dictionary) -> void: pass
	func _draw_mobility_wire(wire: Dictionary) -> void: emitted.append({"kind":"wire","geometry":wire})
	func _draw_player_outline(_command: Dictionary,_style: Dictionary) -> void: pass
	func _draw_telegraph(_hazard: Dictionary) -> void: emitted.append({"kind":"danger"})
	func _sprite(asset: String,point: Vector2,pose: String,_scale: float,_flip := false,_seconds := -1.0) -> void:
		emitted.append({"kind":"sprite","asset":asset,"point":point,"pose":pose})
	func _world_transform(_point: Vector2,_rotation := 0.0,_scale := Vector2.ONE) -> void: pass
	func _world_rect(_texture: Texture2D,rect: Rect2,_tiled: bool,color := Color.WHITE) -> void:
		emitted.append({"kind":"travel_raster","rect":rect,"color":color})
	func capture() -> Array:
		emitted.clear(); mobility_reads = 0; _draw(); return emitted.duplicate(true)

func _state(tick := 1) -> Dictionary:
	var s: Dictionary = City.new()._state()
	s.active_tick = tick; s.event_seq = tick
	s.player.position = [100.0+float(tick-1)*8.0,210.0]
	s.player.velocity = [480.0,0.0]
	s.entities = []; s.projectiles = []
	s.player_mobility = {"schema_version":2,"phase":"boost","cast_id":1,"direction":[1.0,0.0],"progress":float(tick)*8.0,"cancelled":false,"cancel_ticks":0,"anchor":{},"anchors":[{"chunk":["0","0"],"local":[160.0,150.0],"roof_height":32.0},{"chunk":["0","0"],"local":[160.0,270.0],"roof_height":40.0}],"path":[{"chunk":["0","0"],"local":[92.0,210.0],"height":0.0},{"chunk":["0","0"],"local":[220.0,210.0],"height":0.0}]}
	return s

func run(t) -> void:
	var view := Capture.new()
	view.load_manifest()
	var s := _state()
	var before := var_to_bytes(s)
	for viewport in [Vector2(800,450),Vector2(360,800)]:
		view._viewport_size = viewport
		t.check(view.present_city(s,City.new()._terrain()).get("ok",false),"corridor presentation accepts matching terrain")
		var command: Dictionary = view.mobility_commands()
		var wires: Array = command.get("wires",[])
		t.check(wires.size() == 2,"corridor presents both side-anchor wires")
		if wires.size() == 2:
			t.check(wires.all(func(w):return w["from"] == Vector2(100,192)),"both wires originate from grounded player hands")
			t.check(wires[0]["to"] == Vector2(160,118) and wires[1]["to"] == Vector2(160,230),"paired wires use distinct anchor positions and attachment heights")
		t.check(command.height == 0.0 and command.roof_prop_id.is_empty() and command.landing_position == null,"corridor has no roof arc depth override or landing marker")
		var packet: Dictionary = view._city_render_packet()
		var player: Dictionary = packet.upright.filter(func(c):return c.id == "actor:s:player")[0]
		t.check(player.position == Vector2(100,210) and player.depth_y == 210.0,"boost body remains on its normal road-plane depth")
		t.check(not packet.ground.any(func(c):return c.kind == "shadow"),"grounded corridor creates no airborne shadow")
		for reduced in [false,true]:
			view.reduce_effects = reduced
			var raster: Array = view.capture()
			t.check(raster.filter(func(c):return c.kind == "wire").size() == 2,"actual draw emits both wires with reduced effects="+str(reduced))
			var prop_index := -1
			var wire_index := -1
			for index in raster.size():
				if raster[index].get("asset","") == "house_narrow": prop_index = index
				if raster[index].kind == "wire" and wire_index < 0: wire_index = index
			t.check(prop_index >= 0 and wire_index > prop_index,"paired connections stay visible above anchor rooftops without raising the body")
			t.check(raster.any(func(c):return c.kind == "travel_raster" and c.color.g > c.color.r*2.0 and c.color.b > c.color.r*2.0),"actual boost draws distinct cyan travel feedback")
			t.check(raster.back().kind == "danger","danger remains the final layer above corridor feedback")
			t.check(view.mobility_reads == 1,"one draw samples mobility once instead of rebuilding it per pass")
	view.reset_presentation()
	view.observe_render_tick(s)
	var next := _state(2)
	view.observe_render_tick(next); view.begin_render_frame(0.5)
	view.present_city(next,City.new()._terrain())
	var interpolated: Dictionary = view.mobility_commands()
	t.check(interpolated.ground_position == Vector2(104,210) and view._camera == Vector2(104,210),"corridor preserves adjacent-tick player and camera interpolation")
	var wires: Array = interpolated.get("wires",[])
	t.check(wires.size() == 2 and wires.all(func(w):return w["from"] == Vector2(104,192)),"paired wires share interpolated hand position")
	var ground := next.duplicate(true)
	ground.active_tick = 3; ground.event_seq = 3; ground.player_mobility.phase = "ground"
	view.observe_render_tick(ground); view.begin_render_frame(0.0); view.present(ground)
	t.check(view.mobility_commands().get("wires",[]).is_empty() and view.mobility_commands().get("travel",{}).is_empty(),"current ground phase removes wires and boost trail immediately")
	for invalid_kind in ["empty","one_anchor","bad_chunk","far_chunk","nonfinite"]:
		var invalid := _state()
		match invalid_kind:
			"empty": invalid.player_mobility.anchors = []
			"one_anchor": invalid.player_mobility.anchors.resize(1)
			"bad_chunk": invalid.player_mobility.anchors[0].chunk = ["01","0"]
			"far_chunk": invalid.player_mobility.anchors[0].chunk = ["9007199254740993","0"]
			"nonfinite": invalid.player_mobility.anchors[0].local = [INF,0.0]
		view.present(invalid)
		var rejected: Dictionary = view.mobility_commands()
		t.check(rejected.get("wires",[]).is_empty() and rejected.get("travel",{}).is_empty(),"invalid pair never produces a partial attachment or unsupported trail: "+invalid_kind)
	t.check(var_to_bytes(s) == before,"corridor presentation never changes authoritative snapshot bytes")
	view.free()
