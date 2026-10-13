extends RefCounted
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
const Address = preload("res://game/world/world_address.gd")
const World = preload("res://game/presentation/world_view.gd")
const H = preload("res://game/core/streamed_run_world.gd")
# All mobility samples are emitted by the actual Core. The single-house input
# arrangement is a test fixture, not a screenshot of the authored dense city.
class Capture:
	extends "res://game/presentation/world_view.gd"
	var emitted: Array = []
	func _draw_city_ground(_command: Dictionary) -> void: pass
	func _sprite(asset_id: String,point: Vector2,pose: String,scale_value: float,flip: bool = false,seconds: float = -1.0) -> void:
		emitted.append({"kind":"sprite","asset":asset_id,"point":point,"pose":pose})
	func _draw_ground_shadow(command: Dictionary) -> void: emitted.append({"kind":"shadow","position":command.position})
	func _draw_mobility_wire(wire: Dictionary) -> void: emitted.append({"kind":"wire","geometry":wire.duplicate(true)})
	func _draw_landing_marker(point: Vector2) -> void: emitted.append({"kind":"landing","position":point})
	func _draw_player_outline(_command: Dictionary,_style: Dictionary) -> void: emitted.append({"kind":"outline"})
	func _draw_telegraph(_hazard: Dictionary) -> void: emitted.append({"kind":"danger"})
	func capture() -> Array:
		emitted.clear(); _draw(); return emitted.duplicate(true)
func run(t) -> void:
	var view = Capture.new()
	view.load_manifest()
	t.check(view.has_method("mobility_commands"),"WorldView exposes the actual Core mobility projection")
	if not view.has_method("mobility_commands"):
		view.free(); return
	if not F.available(t): view.free(); return
	var script = load(F.PATH)
	for phase in ["rise","over","land"]:
		var s: Dictionary = F.make(t)
		if s.is_empty(): continue
		t.check(F.reach(s,phase),"actual Core reaches visible "+phase)
		if s.state.get("player_mobility",{}).get("phase") != phase: continue
		var snapshot: Dictionary = s.core.snapshot(s.state)
		var terrain: Dictionary = _terrain(s.core,s.state)
		var before: PackedByteArray = var_to_bytes(snapshot)
		for size in [Vector2(360,800),Vector2(800,450)]:
			view._viewport_size = size
			t.check(view.present_city(snapshot,terrain).get("ok",false),"prepared Core terrain accepted in "+str(size))
			var sample: Dictionary = script.visual_sample(snapshot)
			var commands: Dictionary = view.mobility_commands()
			var ground: Vector2 = F.vec(sample.ground_position)
			t.check(commands.get("phase") == phase and is_equal_approx(float(commands.get("height",-1)),float(sample.height)),"view phase/height equal saved Core authority")
			t.check(view._camera == ground and commands.get("ground_position") == ground,"camera follows only plane position, independent of roof height")
			var packet: Dictionary = view._city_render_packet()
			var actors: Array = packet.upright.filter(func(c): return c.id == "actor:s:player")
			t.check(actors.size() == 1,"actual elevated player is emitted exactly once")
			if actors.size() == 1:
				t.check(actors[0].position == ground-Vector2(0,float(sample.height)),"drawn player foot elevation equals actual Core height")
			var shadows: Array = packet.ground.filter(func(c): return c.kind == "shadow")
			t.check(shadows.size() == 1 and shadows[0].position == ground,"ground shadow stays at real planar position")
			var wire: Dictionary = commands.get("wire",{})
			t.check(wire.is_empty() if sample.anchor.is_empty() else not wire.is_empty(),"wire exists exactly while actual Core exposes the active anchor")
			if not wire.is_empty():
				var anchor: Dictionary = sample.anchor
				var endpoint: Dictionary = Address.relative(anchor.chunk,F.vec(anchor.local),snapshot.world.origin_chunk)
				t.check(endpoint.get("ok",false) and wire["to"] == endpoint.local-Vector2(0,float(anchor.roof_height)),"wire endpoint uses stored absolute roof connection in current origin")
				t.check(wire["from"] == ground-Vector2(0,float(sample.height)+18.0),"wire starts at actual elevated character hand")
				if phase == "over":
					var roofs: Array = packet.upright.filter(func(c): return c.id == anchor.prop_id)
					t.check(roofs.size() == 1 and actors.size() == 1 and packet.upright.find(roofs[0]) < packet.upright.find(actors[0]),"over puts actor above its approved roof")
			view.reduce_effects = true
			t.check(view.mobility_commands() == commands,"reduce_effects preserves height, wire and shadow geometry")
			var raster: Array = view.capture()
			var landings: Array = raster.filter(func(c): return c.kind == "landing")
			var landing: Variant = commands.get("landing_position")
			t.check(landings.size() == (1 if landing is Vector2 else 0) and (landings.is_empty() or landings[0].position == landing),"legacy recorder captures the exact essential landing projection")
			t.check(raster.filter(func(c): return c.kind == "shadow").size() == 1,"essential ground shadow reaches the real draw traversal")
			t.check(raster.filter(func(c): return c.kind == "wire").size() == (0 if sample.anchor.is_empty() else 1),"essential wire reaches real traversal even with reduce_effects")
			view.reduce_effects = false
			t.check(var_to_bytes(snapshot) == before,"view never mutates saved Core mobility or snapshot")
		if phase == "over":
			_rebase(t,view,s)
			_cancel_and_restore(t,view,s,script)
	view.free()
func _cancel_and_restore(t,view,s: Dictionary,script) -> void:
	var saved: Dictionary = s.core.snapshot(s.state)
	var cold = F.Core.new(s.provider)
	var restored: Dictionary = cold.restore(saved,s.hydration)
	t.check(restored.get("ok",false),"real cold Core restores the same airborne checkpoint")
	if not restored.get("ok",false): return
	var state: Dictionary = restored.state
	t.check(cold.prepare_world(state,s.hydration).get("ok",false),"cold Core prepares restored airborne geometry")
	t.check(F.same(saved,cold.snapshot(state)),"cold restore preserves exact phase/position before any active tick")
	var terrain: Dictionary = _terrain(cold,state)
	view.present_city(cold.snapshot(state),terrain)
	var before: Dictionary = view.mobility_commands()
	F.F.step(cold,state,Vector2.ZERO)
	var sample: Dictionary = script.visual_sample(cold.snapshot(state))
	view.present_city(cold.snapshot(state),_terrain(cold,state))
	var after: Dictionary = view.mobility_commands()
	t.check(sample.anchor.is_empty() and after.get("wire",{}).is_empty(),"first zero-input restored active tick detaches wire")
	t.check(float(after.get("height",-1)) > 0.0 and is_equal_approx(float(after.height),float(before.height)),"cancelled over retains authority height until safe exit")
	for tick in 40:
		if state.player_mobility.phase == "ground": break
		F.F.step(cold,state,Vector2.ZERO)
	view.present_city(cold.snapshot(state),_terrain(cold,state))
	t.check(state.player_mobility.phase == "ground" and float(view.mobility_commands().height) == 0.0,"real bounded safe landing removes visual height")
	t.check(view._city_render_packet().ground.filter(func(c): return c.kind == "shadow").is_empty(),"landed actual state removes airborne shadow")

func _terrain(core,state: Dictionary) -> Dictionary:
	var result: Dictionary = core.world_render_view(state)
	result.world_revision = core.world_status().get("world_revision",state.world.world_revision)
	return result

func _rebase(t,view,s: Dictionary) -> void:
	var original: Dictionary = s.core.snapshot(s.state)
	view.present_city(original,_terrain(s.core,s.state))
	var before: Dictionary = view.mobility_commands()
	var first_wire: Dictionary = before.get("wire",{})
	var shifted: Dictionary = original.duplicate(true)
	shifted.world.origin_chunk = ["-1","0"]
	shifted.world.origin_revision += 1
	shifted.player.position[0] += 768.0
	var hydration: Dictionary = F.HF.hydration(H.requirements(shifted))
	var cold = F.Core.new(s.provider)
	t.check(cold.prepare_world(shifted,hydration).get("ok",false),"same absolute airborne state prepares in another origin frame")
	view.present_city(cold.snapshot(shifted),_terrain(cold,shifted))
	var after: Dictionary = view.mobility_commands()
	var wire: Dictionary = after.get("wire",{})
	t.check(is_equal_approx(float(before.height),float(after.height)),"origin frame change never changes saved visual height")
	t.check(not wire.is_empty() and not first_wire.is_empty(),"rebase retains actual stored roof connection")
	if not wire.is_empty() and not first_wire.is_empty():
		t.check(wire["from"]-view._camera == first_wire["from"]-before.ground_position and wire["to"]-view._camera == first_wire["to"]-before.ground_position,"wire endpoints remain screen-invariant under exactly one origin translation")
	t.check(shifted.player_mobility == original.player_mobility,"presentation rebase never shifts absolute path or stored anchor")
