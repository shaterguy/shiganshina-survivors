extends RefCounted
const World = preload("res://game/presentation/world_view.gd")
const City = preload("res://tests/city_presentation/test_world_view_city.gd")
const Mobility = preload("res://tests/terrain_mobility/motion_fixture.gd")
const MobilitySample = preload("res://game/core/player_mobility.gd")

# These renderer fixtures exercise real projection, not a replacement interpolator.
# Removing the successful-tick history or using the current camera must fail them.
func run(t) -> void:
	var view = World.new()
	view.load_manifest()
	t.check(view.has_method("observe_render_tick") and view.has_method("set_render_alpha"),"render interpolation has explicit successful-tick and frame-alpha boundaries")
	if not view.has_method("observe_render_tick") or not view.has_method("set_render_alpha"):
		view.free(); return
	_linear_and_identity(t,view)
	_boundaries(t,view)
	_mobility(t,view)
	view.free()

func _state(tick: int, x: float) -> Dictionary:
	var s: Dictionary = City.new()._state()
	s.active_tick = tick
	s.event_seq = tick
	s.player.position = [x,210.0]
	s.player.velocity = [480.0,0.0]
	for entity in s.entities:
		entity.position[0] = x+100.0
		entity.velocity = [480.0,0.0]
		entity.spawned_tick = 0
	s.projectiles[0].position = [x+150.0,220.0]
	s.projectiles[0].velocity = [480.0,0.0]
	s.projectiles[0].attack_id = "render:shot:1"
	s.drops = [{"id":9,"position":[x*0.5+180.0,220.0],"created_tick":0}]
	return s

func _show(view,s: Dictionary,alpha: float) -> void:
	view.begin_render_frame(alpha)
	view.present(s)

func _linear_and_identity(t,view) -> void:
	var a := _state(0,0)
	var b := _state(1,8)
	var before := var_to_bytes([a,b])
	view.observe_render_tick(a)
	view.observe_render_tick(b)
	for alpha in [0.0,0.25,0.5,0.75,1.0]:
		_show(view,b,alpha)
		t.check(is_equal_approx(view._camera.x,8.0*alpha),"camera uses last adjacent tick pair at alpha="+str(alpha))
		var packet: Dictionary = view._city_render_packet()
		t.check(is_equal_approx(view._city_draw_data.actor.player.position.x,view._camera.x),"player and camera share one interpolated plane position")
		t.check(is_equal_approx(view._city_draw_data.actor.rear.position.x,100.0+8.0*alpha),"enemy draw position uses the same alpha")
		t.check(not packet.is_empty(),"interpolated actors enter real depth adapter")
	t.check(var_to_bytes([a,b]) == before,"frame interpolation never mutates accepted Core snapshots")
	_show(view,b,0.5)
	view.present(b)
	t.check(view._camera == Vector2(8,210) and view.mobility_commands().ground_position == Vector2(8,210),"ordinary present remains the exact alpha-one projection")
	view.observe_render_tick(a); view.observe_render_tick(b)
	_show(view,b,0.0)
	t.check(Vector2(b.player.position[0],b.player.position[1]).distance_to(view._camera) == 8.0,"maximum 480px/s display-to-hit discrepancy is exactly one 8px tick")
	view.reset_presentation()
	for tick in 9: view.observe_render_tick(_state(tick,tick*8.0))
	_show(view,_state(8,64),0.5)
	t.check(view._camera == Vector2(60,210),"eight-tick catch-up interpolates tick seven to eight, never prior rendered frame")
	_show(view,_state(8,64),2.0)
	t.check(view._camera == Vector2(64,210),"backlog alpha is clamped without extrapolation")
	_show(view,_state(8,64),NAN)
	t.check(view._camera == Vector2(64,210),"nonfinite alpha uses the current accepted point")

func _boundaries(t,view) -> void:
	view.reset_presentation()
	var a := _state(0,0)
	var b := _state(1,8)
	view.observe_render_tick(a)
	view.observe_render_tick(b)
	var shifted := _state(2,16)
	shifted.world.origin_chunk = ["-1","0"]
	shifted.world.origin_revision = 1
	for group in [[shifted.player],shifted.entities,shifted.projectiles,shifted.drops]:
		for actor in group: actor.position[0] += 768.0
	view.observe_render_tick(shifted)
	_show(view,shifted,0.5)
	t.check(view._camera == Vector2(780,210),"origin rebase translates previous endpoint once before lerp")
	t.check(view._screen(Vector2(868,210)).x-view._viewport_size.x*0.5 == 88.0,"static terrain shares the current-origin interpolated camera")
	view.set_render_alpha(0.5,true)
	t.check(view._camera == Vector2(784,210),"paused or held frame snaps to current and discards old interval")
	_show(view,shifted,0.0)
	t.check(view._camera == Vector2(784,210),"resume cannot move backwards through pre-pause history")
	for kind in ["restore","new_run","teleport","same_tick","scene","tick_gap"]:
		view.reset_presentation()
		view.observe_render_tick(a); view.observe_render_tick(b)
		var next := _state(2,16)
		match kind:
			"restore": next.active_tick = 0; next.event_seq = 0
			"new_run": next.run_id = "other-run"
			"teleport": next.player.position[0] = 900.0
			"same_tick": next.active_tick = 1; next.event_seq = 1
			"scene": next.world.stage = "dock"; next.world.scene_id = "authored_dock"
			"tick_gap": next.active_tick = 4
		view.observe_render_tick(next)
		_show(view,next,0.0)
		t.check(view._camera == Vector2(next.player.position[0],next.player.position[1]),"discontinuous "+kind+" does not smear old coordinates")
	view.reset_presentation()
	view.observe_render_tick(a); view.observe_render_tick(b)
	var next := _state(2,16)
	next.entities[0].spawned_tick = 2
	next.entities[0].position[0] = 120.0
	view.observe_render_tick(next); _show(view,next,0.0)
	view._city_render_packet()
	t.check(view._city_draw_data.actor.rear.position.x == 120.0,"reused entity identity starts at its own current position")
	view.reset_presentation(); view.present(next); view.set_render_alpha(0.0)
	t.check(view._camera.x == 16.0,"cold presentation has no synthetic previous state")

func _mobility(t,view) -> void:
	var s: Dictionary = Mobility.make(t)
	if s.is_empty() or not Mobility.reach(s,"rise"): return
	view.reset_presentation()
	var a: Dictionary = s.core.snapshot(s.state)
	view.observe_render_tick(a)
	Mobility.step(s)
	var b: Dictionary = s.core.snapshot(s.state)
	var bytes := var_to_bytes(b)
	view.observe_render_tick(b)
	var terrain: Dictionary = s.core.world_render_view(s.state)
	terrain.world_revision = s.core.world_status().world_revision
	view.begin_render_frame(0.5)
	t.check(view.present_city(b,terrain).get("ok",false),"real airborne Core sample enters prepared city renderer")
	view.set_render_alpha(0.5)
	var first: Dictionary = MobilitySample.visual_sample(a)
	var last: Dictionary = MobilitySample.visual_sample(b)
	var expected_ground := Mobility.vec(first.ground_position).lerp(Mobility.vec(last.ground_position),0.5)
	var expected_height := lerpf(float(first.height),float(last.height),0.5)
	var command: Dictionary = view.mobility_commands()
	t.check(command.ground_position.is_equal_approx(expected_ground) and is_equal_approx(command.height,expected_height),"ground and mobility height share adjacent-tick alpha")
	t.check(view._camera.is_equal_approx(expected_ground),"camera tracks interpolated ground instead of airborne height")
	t.check(command.wire["from"].is_equal_approx(expected_ground-Vector2(0,expected_height+18.0)),"wire starts at the same interpolated elevated hand")
	var packet: Dictionary = view._city_render_packet()
	var actors: Array = packet.upright.filter(func(c): return c.id == "actor:s:player")
	t.check(actors.size() == 1 and actors[0].position.is_equal_approx(expected_ground-Vector2(0,expected_height)),"visible body and shadow use consistent mobility projection")
	t.check(var_to_bytes(b) == bytes,"height interpolation leaves Core mobility and path bytes intact")
	Mobility.step(s,Vector2.ZERO)
	var cancelled: Dictionary = s.core.snapshot(s.state)
	view.observe_render_tick(cancelled); view.begin_render_frame(0.0); view.present(cancelled)
	t.check(view.mobility_commands().wire.is_empty(),"authoritative cancellation removes the wire without one-tick delay")
