extends RefCounted
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
# The only double is the raster/GPU boundary. These checks run real present(),
# _draw(), action selection and atlas selection. Time-only sprite selection,
# velocity integration, shared phases or a missing discontinuity guard must fail.
class CaptureView extends "res://game/presentation/world_view.gd":
	var sprites: Array[Dictionary] = []
	func _draw_city() -> void: pass
	func _draw_props() -> void: pass
	func _sprite(asset_id: String, world: Vector2, animation: String, scale_value: float, flip := false, seconds := -1.0) -> void:
		sprites.append({"asset":asset_id,"world":world,"animation":animation,"scale":scale_value,"flip":flip,"region":frame_rect(asset_id,animation,_clock if seconds < 0 else seconds)})
	func capture() -> Array[Dictionary]:
		sprites.clear()
		_draw()
		return sprites.duplicate(true)

func _asset(gait := true) -> Dictionary:
	var record := {"cell_w":192,"cell_h":256,"columns":8,"animations":{"idle":{"frames":[0],"fps":1,"loop":true},"move":{"frames":range(12,76),"fps":64,"loop":true},"windup":{"frames":[1],"fps":1},"attack":{"frames":[2],"fps":1},"hit":{"frames":[3],"fps":1},"death":{"frames":[4],"fps":1}}}
	if gait: record.gait = {"cycle_distance_px":64.0}
	return record
func _view():
	var view := CaptureView.new()
	view._assets = {"garrison_01":_asset(),"titan_basic":_asset(),"armored_titan":_asset()}
	return view
func _enemy(id := 7, x := 100.0, action := "move", started := 0) -> Dictionary:
	return {"id":id,"enemy_id":"basic","position":[x,100.0],"velocity":[600.0,0.0],"facing":[1.0,0.0],"hp":100.0,"speed":600.0,"spawned_tick":0,"action_state":action,"action_started_tick":started}
func _snapshot(tick: int, player_x := 0.0, enemies: Array = []) -> Dictionary:
	return {"seed":42,"chapter_id":"chapter_01_shiganshina","content_revision":"ch01.2","active_tick":tick,"survival_tick":tick,"phase":"survival","pause_reasons":[],"player":{"id":"player","position":[player_x,0.0],"velocity":[600.0,0.0],"facing":[1.0,0.0],"hp":100.0},"entities":enemies,"rules":{"move_speed":600.0,"enemy_catalog":{"basic":{"art_id":"titan_basic"}}},"escape_zone":[0,300,100,100]}
func _region(view, asset := "garrison_01", x := INF) -> Rect2:
	for sprite in view.capture():
		if sprite.asset == asset and (not is_finite(x) or is_equal_approx(sprite.world.x,x)): return sprite.region
	return Rect2()

func run(t) -> void:
	_distance_and_independence(t)
	_pause_and_transitions(t)
	_discontinuities_and_cleanup(t)
	_optional_metadata_and_final_threat(t)
	_real_core_wall_and_pause(t)
	_real_core_single_tick_steps(t)
	_grounded_idle_and_excluded_player_actions(t)
	_native_stride_and_grounded_guard(t)

func _distance_and_independence(t) -> void:
	var view = _view()
	view.present(_snapshot(0,0.0,[_enemy(7,100.0),_enemy(8,200.0)]))
	view._clock = 9.0
	t.check(_region(view) == Rect2(768,256,192,256),"first observation starts gait at move frame12 regardless of render clock")
	view.present(_snapshot(1,8.0,[_enemy(7,104.0),_enemy(8,200.0)]))
	t.check(_region(view) == Rect2(768,512,192,256),"eight world pixels select move frame20 rather than elapsed-time frame")
	t.check(_region(view,"titan_basic",104.0) == Rect2(0,512,192,256),"each enemy has an independent actual-distance phase")
	t.check(_region(view,"titan_basic",200.0) == Rect2(768,256,192,256),"blocked enemy with nonzero velocity does not walk in place")
	view.present(_snapshot(2,0.0,[_enemy(7,104.0),_enemy(8,202.0)]))
	t.check(_region(view) == Rect2(768,768,192,256),"reversed world travel adds positive distance rather than cancelling it")
	var vertical := _snapshot(3,0.0)
	vertical.player.position[1] = 8.0
	vertical.player.velocity = [0.0,600.0]
	view.present(vertical)
	t.check(_region(view) == Rect2(768,1024,192,256),"vertical travel uses world-space distance rather than screen x displacement")
	view.present(_snapshot(4,0.0))
	t.check(_region(view) == Rect2(768,1280,192,256),"world-space return travel continues the same gait cycle")
	for tick in range(5,9): view.present(_snapshot(tick,float(tick-4)*8.0))
	t.check(_region(view) == Rect2(768,256,192,256),"one native stride loops exactly to the first movement frame")
	t.check(view.has_method("movement_seconds"),"distance gait supports explicit display-scale conversion")
	if view.has_method("movement_seconds"):
		view.present(_snapshot(9,40.0))
		var seconds: float = view.movement_seconds("garrison_01","player",2.0,0.0)
		t.check(view.frame_rect("garrison_01","move",seconds) == Rect2(0,1536,192,256),"double display scale requires twice the world distance per cycle")
	view.free()

func _real_core_wall_and_pause(t) -> void:
	var view = _view()
	var chapter := Fixture.geometry_chapter({"bounds":[-64,-64,128,128],"obstacles":[]},[0,0])
	var sim = Fixture.geometry_sim(chapter)
	var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
	var commands: Array[Dictionary] = []
	view.present(sim.snapshot(state))
	for tick in range(40):
		sim.step(state,Vector2.RIGHT,commands)
		view.present(sim.snapshot(state))
	t.check(is_equal_approx(float(state.player.position[0]),56.0),"real core fixture reaches its collision boundary")
	# All 56 world pixels, including the first idle-to-move step, choose
	# frame 12+56=68, column4 row8 in this independent atlas.
	t.check(_region(view) == Rect2(768,2048,192,256),"real collision-limited position counts every traveled pixel including the initial step")
	for tick in range(30):
		sim.step(state,Vector2.RIGHT,commands)
		view.present(sim.snapshot(state))
	t.check(_region(view) == Rect2(768,2048,192,256),"holding movement against a real wall cannot advance gait")
	sim.set_pause(state,"rotation",true)
	for tick in range(10):
		sim.step(state,Vector2.LEFT,commands)
		view.present(sim.snapshot(state))
	t.check(_region(view) == Rect2(768,2048,192,256),"real core rotation pause preserves the collision-stopped gait")
	sim.set_pause(state,"rotation",false)
	for tick in range(4):
		sim.step(state,Vector2.LEFT,commands)
		view.present(sim.snapshot(state))
	t.check(_region(view) == Rect2(1152,256,192,256),"real core resume adds only ten pixels actually walked at 150 px/s")
	view.free()

func _real_core_single_tick_steps(t) -> void:
	var view = _view()
	var sim = Fixture.simulation(t)
	var state: Dictionary = sim.new_run(Fixture.chapter(),42,Fixture.run_config())
	var commands: Array[Dictionary] = []
	view.present(sim.snapshot(state))
	for step in range(8):
		sim.step(state,Vector2.RIGHT,commands)
		view.present(sim.snapshot(state))
		if step == 7:
			t.check(is_equal_approx(float(state.player.position[0]),20.0),"eight real single-tick inputs move twenty pixels at 150 px/s")
			t.check(_region(view) == Rect2(0,1024,192,256),"repeated single-tick steps separated by idle advance the rendered gait to frame32")
		sim.step(state,Vector2.ZERO,commands)
		view.present(sim.snapshot(state))
		t.check(_region(view) == Rect2(0,0,192,256),"zero-input samples still render idle while preserving accumulated walking phase")
	view.free()

func _grounded_idle_and_excluded_player_actions(t) -> void:
	var view = _view()
	view.present(_snapshot(0,0.0,[_enemy()]))
	view.present(_snapshot(1,8.0,[_enemy(7,108.0)]))
	view.present(_snapshot(2,16.0,[_enemy(7,116.0,"idle",2)]))
	t.check(_region(view,"titan_basic") == Rect2(768,512,192,256),"displacement during explicit grounded idle does not add walking distance")
	view.present(_snapshot(3,24.0,[_enemy(7,124.0,"move",3)]))
	t.check(_region(view,"titan_basic") == Rect2(768,768,192,256),"first grounded move after idle counts its actual displacement")
	var hit: Array[Dictionary] = [{"type":"damage","payload":{"target_id":"player","hp":90}}]
	view.consume_events(hit)
	view.present(_snapshot(4,32.0))
	view._hit_until = 0.0
	view.present(_snapshot(5,40.0))
	t.check(_region(view) == Rect2(768,1024,192,256),"player hit and hit-to-move displacement remain excluded from gait")
	var attack: Array[Dictionary] = [{"type":"damage","payload":{"target_id":"7","hp":90}}]
	view.consume_events(attack)
	view.present(_snapshot(6,48.0))
	view._attack_until = 0.0
	view.present(_snapshot(7,56.0))
	t.check(_region(view) == Rect2(768,1024,192,256),"player attack and attack-to-move displacement remain excluded from gait")
	view.free()

func _native_stride_and_grounded_guard(t) -> void:
	var view = _view()
	view._assets.garrison_01.gait.cycle_distance_px = 123.333333333333
	view.present(_snapshot(0))
	for tick in range(1,9): view.present(_snapshot(tick,float(tick)*7.708333333333))
	t.check(_region(view) == Rect2(768,1280,192,256),"approved native 123.333333 pixel stride reaches the opposite leg at half a cycle")
	var airborne := _snapshot(9,69.375)
	airborne.player.grounded = false
	view.present(airborne)
	view.present(_snapshot(10,77.083333333333))
	t.check(_region(view) == Rect2(768,1280,192,256),"explicit airborne flag and landing cannot add player walking distance")
	view.free()

func _pause_and_transitions(t) -> void:
	var view = _view()
	view.present(_snapshot(0,0.0,[_enemy()]))
	var current := _snapshot(1,8.0,[_enemy(7,108.0)])
	view.present(current)
	for index in range(4): view.present(current.duplicate(true))
	view._clock = 90.0
	view._viewport_size = Vector2(450,800)
	t.check(_region(view) == Rect2(768,512,192,256),"repeated present calls, clock advance and rotation preserve gait phase")
	current.pause_reasons = ["user","rotation"]
	view.present(current)
	t.check(_region(view) == Rect2(768,512,192,256),"pause preserves the selected gait frame")
	current = _snapshot(2,16.0,[_enemy(7,116.0)])
	current.pause_reasons = ["user"]
	view.present(current)
	current.pause_reasons = []
	view.present(current)
	view.present(_snapshot(3,24.0,[_enemy(7,124.0)]))
	t.check(_region(view) == Rect2(768,768,192,256),"paused coordinates are rebased without accumulating movement")
	for action in ["windup","attack","airborne","recover"]:
		view.present(_snapshot(4,24.0,[_enemy(7,132.0,action,4)]))
		view.present(_snapshot(5,24.0,[_enemy(7,140.0,action,4)]))
		view.present(_snapshot(6,24.0,[_enemy(7,148.0,"move",6)]))
		t.check(_region(view,"titan_basic") == Rect2(768,768,192,256),action+" displacement and the return-to-move transition do not advance gait")
		# Restart tick sequence without retaining the prior loop's test positions.
		view.free()
		view = _view()
		view.present(_snapshot(0,0.0,[_enemy()]))
		view.present(_snapshot(1,8.0,[_enemy(7,108.0)]))
		view.present(_snapshot(2,16.0,[_enemy(7,116.0)]))
	view.present(_snapshot(3,16.0,[_enemy(7,124.0,"move",3)]))
	t.check(_region(view,"titan_basic") == Rect2(768,768,192,256),"a skipped action sequence cannot count a landing as grounded travel")
	var events: Array[Dictionary] = [{"type":"damage","payload":{"target_id":"7","hp":90}}]
	view.consume_events(events)
	view.present(_snapshot(4,24.0,[_enemy(7,132.0,"move",3)]))
	view._enemy_hits.clear()
	view._attack_until = 0.0
	view.present(_snapshot(5,32.0,[_enemy(7,140.0,"move",3)]))
	t.check(_region(view,"titan_basic") == Rect2(768,768,192,256),"hit displacement and hit-to-move transition do not advance gait")
	view.free()

func _discontinuities_and_cleanup(t) -> void:
	var view = _view()
	view.present(_snapshot(0,0.0,[_enemy()]))
	view.present(_snapshot(1,8.0,[_enemy(7,108.0)]))
	view.present(_snapshot(2,1000.0,[_enemy(7,1000.0)]))
	t.check(_region(view) == Rect2(768,512,192,256),"teleport beyond observed movement speed is not stride distance")
	view.present(_snapshot(3,1008.0,[_enemy(7,1008.0)]))
	t.check(_region(view) == Rect2(768,768,192,256),"walking resumes from the rebased teleport location")
	view.present(_snapshot(100,1016.0,[_enemy(7,1016.0)]))
	t.check(_region(view) == Rect2(768,768,192,256),"unobserved checkpoint jump does not synthesize gait distance")
	view.present(_snapshot(101,1024.0))
	view.present(_snapshot(102,1032.0,[_enemy(7,1024.0)]))
	t.check(_region(view,"titan_basic") == Rect2(768,256,192,256),"removed entity ID reappearance starts a fresh gait")
	var dead := _enemy(7,1032.0)
	dead.hp = 0.0
	view.present(_snapshot(103,1040.0,[dead]))
	view.present(_snapshot(104,1048.0,[_enemy(7,1040.0)]))
	t.check(_region(view,"titan_basic") == Rect2(768,256,192,256),"dead actor phase is discarded before its ID can be reused")
	view.present(_snapshot(105,1056.0,[_enemy(7,1048.0)]))
	var replacement := _enemy(7,1056.0)
	replacement.spawned_tick = 106
	view.present(_snapshot(106,1064.0,[replacement]))
	t.check(_region(view,"titan_basic") == Rect2(768,256,192,256),"changed spawn identity resets reused entity ID")
	view.present(_snapshot(0,0.0,[_enemy()]))
	t.check(_region(view) == Rect2(768,256,192,256),"tick rewind resets prior-run gait")
	view.present(_snapshot(1,8.0))
	var new_seed := _snapshot(2,16.0)
	new_seed.seed = 43
	view.present(new_seed)
	t.check(_region(view) == Rect2(768,256,192,256),"new run seed resets gait even with increasing tick")
	view.present(_snapshot(3,24.0))
	view.present(_snapshot(4,32.0))
	t.check(view.has_method("reset_presentation"),"run lifecycle can reset identical-seed identical-tick presentation state")
	if view.has_method("reset_presentation"):
		view.reset_presentation()
		view.present(_snapshot(4,32.0))
		t.check(_region(view) == Rect2(768,256,192,256),"explicit new-run reset prevents same-tick same-ID gait carryover")
	view.present(_snapshot(5,40.0))
	view.present({})
	view.present(_snapshot(6,48.0))
	t.check(_region(view) == Rect2(768,256,192,256),"title-state clear drops every previous actor phase")
	view.free()

func _optional_metadata_and_final_threat(t) -> void:
	var view = _view()
	view._assets.garrison_01 = _asset(false)
	view.present(_snapshot(0))
	view._clock = 0.125
	t.check(_region(view) == Rect2(768,512,192,256),"assets without gait metadata retain their original time-based animation")
	for invalid in [0.0,-1.0,"invalid",INF]:
		view._assets.garrison_01.gait = {"cycle_distance_px":invalid}
		view.present(_snapshot(1))
		t.check(_region(view) == Rect2(768,512,192,256),"invalid gait metadata safely retains legacy frame selection")
	var evacuation := _snapshot(108000)
	evacuation.phase = "evacuation"
	view.present(evacuation)
	for sprite in view.capture():
		if sprite.asset == "armored_titan":
			t.check(sprite.animation == "idle" and sprite.region == Rect2(0,0,192,256),"fixed-position final armored threat stays idle until authored world motion exists")
	view.free()
