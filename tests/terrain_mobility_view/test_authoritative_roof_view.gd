extends RefCounted
const F = preload("res://tests/corridor_mobility_presentation/presentation_fixture.gd")
const Address = preload("res://game/world/world_address.gd")
const H = preload("res://game/core/streamed_run_world.gd")
# Historical file name retained; all motion below comes from real corridor Core.
class Capture:
	extends "res://game/presentation/world_view.gd"
	var emitted: Array = []
	func _draw_city_ground(_command: Dictionary) -> void: pass
	func _sprite(asset_id: String,point: Vector2,pose: String,_scale_value: float,_flip: bool = false,_seconds: float = -1.0) -> void:
		emitted.append({"kind":"sprite","asset":asset_id,"point":point,"pose":pose})
	func _draw_ground_shadow(command: Dictionary) -> void: emitted.append({"kind":"shadow","position":command.position})
	func _draw_mobility_wire(wire: Dictionary) -> void: emitted.append({"kind":"wire","geometry":wire.duplicate(true)})
	func _draw_mobility_travel(travel: Dictionary) -> void: emitted.append({"kind":"travel","geometry":travel.duplicate(true)})
	func _draw_player_outline(_command: Dictionary,_style: Dictionary) -> void: emitted.append({"kind":"outline"})
	func _draw_telegraph(_hazard: Dictionary) -> void: emitted.append({"kind":"danger"})
	func capture() -> Array:
		emitted.clear(); _draw(); return emitted.duplicate(true)
func run(t) -> void:
	var view = Capture.new()
	view.load_manifest()
	if not F.available(t): view.free(); return
	for additional_ticks in [0,1,2]:
		var s: Dictionary = F.make(t)
		if s.is_empty(): continue
		t.check(F.reach(s,"boost"),"actual Core reaches visible corridor boost")
		for tick in additional_ticks: F.step(s)
		if s.state.get("player_mobility",{}).get("phase") != "boost": continue
		var snapshot: Dictionary = s.core.snapshot(s.state)
		var before: PackedByteArray = var_to_bytes(snapshot)
		for size in [Vector2(360,800),Vector2(800,450)]:
			view._viewport_size = size
			t.check(view.present_city(snapshot,_terrain(s.core,s.state)).get("ok",false),"prepared corridor terrain accepted in "+str(size))
			var sample: Dictionary = load(F.PATH).visual_sample(snapshot)
			var commands: Dictionary = view.mobility_commands()
			var ground: Vector2 = F.vec(sample.ground_position)
			t.check(commands.phase == "boost" and commands.height == 0.0 and sample.height == 0.0,"view projects zero-height Core corridor authority")
			t.check(view._camera == ground and commands.ground_position == ground,"camera follows real road-plane position")
			var packet: Dictionary = view._city_render_packet()
			var actors: Array = packet.upright.filter(func(c): return c.id == "actor:s:player")
			t.check(actors.size() == 1 and actors[0].position == ground and actors[0].depth_y == ground.y,"player is emitted once at ordinary ground depth")
			t.check(packet.ground.filter(func(c): return c.kind == "shadow").is_empty(),"corridor never creates airborne shadow")
			var wires: Array = commands.wires
			t.check(wires.size() == 2 and sample.anchors.size() == 2,"both actual Core side anchors produce wires")
			for index in mini(wires.size(),sample.anchors.size()):
				var anchor: Dictionary = sample.anchors[index]
				var endpoint: Dictionary = Address.relative(anchor.chunk,F.vec(anchor.local),snapshot.world.origin_chunk)
				t.check(endpoint.get("ok",false) and wires[index]["to"] == endpoint.local-Vector2(0,float(anchor.roof_height)),"wire endpoint uses stored absolute side connection")
				t.check(wires[index]["from"] == ground-Vector2(0,18),"wire starts at grounded character hand")
			view.reduce_effects = true
			t.check(view.mobility_commands() == commands,"reduce_effects preserves paired attachment and travel geometry")
			var raster: Array = view.capture()
			t.check(commands.landing_position == null and commands.roof_prop_id.is_empty(),"road travel has no landing marker or roof depth privilege")
			t.check(raster.filter(func(c): return c.kind == "shadow").is_empty(),"actual corridor draw never emits airborne shadow")
			t.check(raster.filter(func(c): return c.kind == "wire").size() == 2 and raster.filter(func(c): return c.kind == "travel").size() == 1,"essential paired wires and travel feedback survive reduced effects")
			view.reduce_effects = false
			t.check(var_to_bytes(snapshot) == before,"view never mutates Core mobility or snapshot")
		if additional_ticks == 0:
			_rebase(t,view,s)
			_cancel_and_restore(t,view,s)
	view.free()
func _cancel_and_restore(t,view,s: Dictionary) -> void:
	var saved: Dictionary = s.core.snapshot(s.state)
	var cold = F.Core.new(s.provider)
	var restored: Dictionary = cold.restore(saved,s.hydration)
	t.check(restored.get("ok",false),"cold Core restores the same corridor checkpoint")
	if not restored.get("ok",false): return
	var state: Dictionary = restored.state
	t.check(cold.prepare_world(state,s.hydration).get("ok",false),"cold Core prepares restored corridor geometry")
	t.check(F.same(saved,cold.snapshot(state)),"cold restore preserves exact corridor before an active tick")
	view.present_city(cold.snapshot(state),_terrain(cold,state))
	t.check(view.mobility_commands().wires.size() == 2,"restored active corridor redraws both wires")
	F.F.step(cold,state,Vector2.ZERO)
	view.present_city(cold.snapshot(state),_terrain(cold,state))
	var after: Dictionary = view.mobility_commands()
	t.check(state.player_mobility.phase == "ground" and after.wires.is_empty(),"zero input detaches both wires and stops corridor immediately")
	t.check(after.height == 0.0 and after.travel.is_empty(),"interruption has no floating exit or false landing trail")
	t.check(view._city_render_packet().ground.filter(func(c): return c.kind == "shadow").is_empty(),"interrupted ground state has no airborne shadow")
func _terrain(core,state: Dictionary) -> Dictionary:
	var result: Dictionary = core.world_render_view(state)
	result.world_revision = core.world_status().get("world_revision",state.world.world_revision)
	return result
func _rebase(t,view,s: Dictionary) -> void:
	var original: Dictionary = s.core.snapshot(s.state)
	view.present_city(original,_terrain(s.core,s.state))
	var before: Dictionary = view.mobility_commands()
	var shifted: Dictionary = original.duplicate(true)
	shifted.world.origin_chunk = ["-1","0"]
	shifted.world.origin_revision += 1
	shifted.player.position[0] += 768.0
	var hydration: Dictionary = F.HF.hydration(H.requirements(shifted))
	var cold = F.Core.new(s.provider)
	t.check(cold.prepare_world(shifted,hydration).get("ok",false),"same absolute corridor prepares in another origin frame")
	view.present_city(cold.snapshot(shifted),_terrain(cold,shifted))
	var after: Dictionary = view.mobility_commands()
	t.check(before.height == 0.0 and after.height == 0.0,"origin change never invents visual elevation")
	t.check(after.wires.size() == 2 and before.wires.size() == 2,"rebase retains both stored side connections")
	for index in mini(after.wires.size(),before.wires.size()):
		t.check(after.wires[index]["from"]-view._camera == before.wires[index]["from"]-before.ground_position and after.wires[index]["to"]-view._camera == before.wires[index]["to"]-before.ground_position,"paired endpoints remain screen-invariant under one origin translation")
	t.check(shifted.player_mobility == original.player_mobility,"presentation rebase never shifts absolute corridor or anchors")
